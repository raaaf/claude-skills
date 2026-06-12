#!/usr/bin/env bash
#
# check-i18n-keys.sh — deterministic i18n completeness check.
#
# Compares translation key sets across locales. A key present in one locale
# but missing in another is a real bug (renders raw key or falls back
# silently), and diffing key sets is a job for bash, not an LLM.
#
# Supports:
#   - Laravel dir layout:  lang/{locale}/*.php, resources/lang/{locale}/*.php
#   - Flat JSON layout:    {dir}/{locale}.json  (locales/, lang/, i18n/, translations/)
#
# Output:
#   I18N_RESULT=OK | MISSING | SKIP
#   For MISSING: one line per gap: "MISSING {locale}: {file-or-key}"
#
# Usage: bash check-i18n-keys.sh [PROJECT_ROOT]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- locate translation base dir (web layouts; native modes C/D run regardless)
BASE=""
for candidate in "$ROOT/resources/lang" "$ROOT/lang" "$ROOT/locales" "$ROOT/translations" "$ROOT/i18n"; do
  [ -d "$candidate" ] && { BASE="$candidate"; break; }
done

MISSING_COUNT=0
FOUND_ANY_SOURCE=0

# Locale-gated keys: projects may render different key sets per locale on
# purpose (e.g. locale-specific landing pages). Prefixes listed in
# .claude/audits/i18n-locale-gated.txt (one per line, # comments allowed)
# are excluded from key-level gap reporting.
GATED_PREFIXES=()
GATED_FILE="$ROOT/.claude/audits/i18n-locale-gated.txt"
if [ -f "$GATED_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && GATED_PREFIXES+=("$line")
  done < "$GATED_FILE"
fi

is_gated() {
  local key="$1" prefix
  for prefix in "${GATED_PREFIXES[@]+"${GATED_PREFIXES[@]}"}"; do
    case "$key" in "$prefix"*) return 0 ;; esac
  done
  return 1
}

report() {
  is_gated "$2" && return 0
  echo "MISSING $1: $2"
  MISSING_COUNT=$((MISSING_COUNT + 1))
}

# --- Mode A: per-locale subdirectories (Laravel) ------------------------------
LOCALE_DIRS=()
if [ -n "$BASE" ]; then
  while IFS= read -r d; do
    name=$(basename "$d")
    # locale dirs are short: de, en, fr, de_DE, pt-BR, vendor excluded
    if [[ "$name" =~ ^[a-z]{2}([_-][A-Za-z]{2})?$ ]]; then
      LOCALE_DIRS+=("$d")
    fi
  done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [ "${#LOCALE_DIRS[@]}" -ge 2 ]; then
  FOUND_ANY_SOURCE=1
  REF="${LOCALE_DIRS[0]}"
  REF_NAME=$(basename "$REF")

  # 1) file-level diff in both directions
  for dir in "${LOCALE_DIRS[@]}"; do
    [ "$dir" = "$REF" ] && continue
    loc=$(basename "$dir")
    comm -23 <(cd "$REF" && find . -type f \( -name "*.php" -o -name "*.json" \) | sort) \
             <(cd "$dir" && find . -type f \( -name "*.php" -o -name "*.json" \) | sort) \
      | while read -r f; do echo "MISSING $loc: file ${f#./}"; done
    comm -13 <(cd "$REF" && find . -type f \( -name "*.php" -o -name "*.json" \) | sort) \
             <(cd "$dir" && find . -type f \( -name "*.php" -o -name "*.json" \) | sort) \
      | while read -r f; do echo "MISSING $REF_NAME: file ${f#./}"; done
  done > /tmp/i18n-file-gaps.$$

  cat /tmp/i18n-file-gaps.$$
  MISSING_COUNT=$(wc -l < /tmp/i18n-file-gaps.$$ | tr -d ' ')
  rm -f /tmp/i18n-file-gaps.$$

  # 2) key-level diff for PHP files (requires php)
  if command -v php >/dev/null 2>&1; then
    dump_php_keys() {
      php -r '
        function flat($a, $p = "") {
          foreach ($a as $k => $v) {
            $key = $p === "" ? $k : "$p.$k";
            if (is_array($v)) { flat($v, $key); } else { echo $key, "\n"; }
          }
        }
        $f = $argv[1];
        $a = @include $f;
        if (is_array($a)) flat($a);
      ' "$1" 2>/dev/null | sort
    }
    for dir in "${LOCALE_DIRS[@]}"; do
      [ "$dir" = "$REF" ] && continue
      loc=$(basename "$dir")
      while IFS= read -r relfile; do
        ref_file="$REF/$relfile"
        loc_file="$dir/$relfile"
        [ -f "$ref_file" ] && [ -f "$loc_file" ] || continue
        gaps=$(comm -23 <(dump_php_keys "$ref_file") <(dump_php_keys "$loc_file"))
        rev_gaps=$(comm -13 <(dump_php_keys "$ref_file") <(dump_php_keys "$loc_file"))
        [ -n "$gaps" ] && while IFS= read -r k; do report "$loc" "${relfile%.php}.$k"; done <<< "$gaps"
        [ -n "$rev_gaps" ] && while IFS= read -r k; do report "$REF_NAME" "${relfile%.php}.$k"; done <<< "$rev_gaps"
      done < <(cd "$REF" && find . -type f -name "*.php" | sed 's|^\./||')
    done
  fi
fi

# --- Mode B: flat per-locale JSON files ({locale}.json) -----------------------
JSON_FILES=()
if [ -n "$BASE" ]; then
  while IFS= read -r f; do
    name=$(basename "$f" .json)
    [[ "$name" =~ ^[a-z]{2}([_-][A-Za-z]{2})?$ ]] && JSON_FILES+=("$f")
  done < <(find "$BASE" -maxdepth 1 -type f -name "*.json" | sort)
fi

if [ "${#JSON_FILES[@]}" -ge 2 ] && command -v jq >/dev/null 2>&1; then
  FOUND_ANY_SOURCE=1
  REF_JSON="${JSON_FILES[0]}"
  REF_JSON_NAME=$(basename "$REF_JSON" .json)
  dump_json_keys() { jq -r 'paths(scalars) | join(".")' "$1" 2>/dev/null | sort; }
  for f in "${JSON_FILES[@]}"; do
    [ "$f" = "$REF_JSON" ] && continue
    loc=$(basename "$f" .json)
    gaps=$(comm -23 <(dump_json_keys "$REF_JSON") <(dump_json_keys "$f"))
    rev_gaps=$(comm -13 <(dump_json_keys "$REF_JSON") <(dump_json_keys "$f"))
    [ -n "$gaps" ] && while IFS= read -r k; do report "$loc" "$k"; done <<< "$gaps"
    [ -n "$rev_gaps" ] && while IFS= read -r k; do report "$REF_JSON_NAME" "$k"; done <<< "$rev_gaps"
  done
fi

# --- Mode C: iOS .lproj bundles (Localizable.strings) -------------------------
LPROJ_DIRS=()
while IFS= read -r d; do
  LPROJ_DIRS+=("$d")
done < <(find "$ROOT" -type d -name "*.lproj" -not -path "*/build/*" -not -path "*/Pods/*" -not -path "*/DerivedData/*" 2>/dev/null | grep -v "Base.lproj" | sort)

if [ "${#LPROJ_DIRS[@]}" -ge 2 ]; then
  FOUND_ANY_SOURCE=1
  dump_strings_keys() {
    # Lines like: "key" = "value";  (also matches unquoted keys)
    grep -oE '^[[:space:]]*"[^"]+"[[:space:]]*=' "$1" 2>/dev/null \
      | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' | sort -u
  }
  REF_LPROJ="${LPROJ_DIRS[0]}"
  REF_LPROJ_NAME=$(basename "$REF_LPROJ" .lproj)
  for d in "${LPROJ_DIRS[@]:1}"; do
    loc=$(basename "$d" .lproj)
    while IFS= read -r relfile; do
      ref_file="$REF_LPROJ/$relfile"
      loc_file="$d/$relfile"
      if [ ! -f "$loc_file" ]; then report "$loc" "file $relfile"; continue; fi
      gaps=$(comm -23 <(dump_strings_keys "$ref_file") <(dump_strings_keys "$loc_file"))
      rev_gaps=$(comm -13 <(dump_strings_keys "$ref_file") <(dump_strings_keys "$loc_file"))
      [ -n "$gaps" ] && while IFS= read -r k; do report "$loc" "$k"; done <<< "$gaps"
      [ -n "$rev_gaps" ] && while IFS= read -r k; do report "$REF_LPROJ_NAME" "$k"; done <<< "$rev_gaps"
    done < <(cd "$REF_LPROJ" && find . -maxdepth 1 -name "*.strings" | sed 's|^\./||')
  done
fi

# --- Mode D: Android values dirs (strings.xml) ---------------------------------
ANDROID_DEFAULT=$(find "$ROOT" -type d -name "values" -path "*/res/values" -not -path "*/build/*" 2>/dev/null | head -1)
if [ -n "$ANDROID_DEFAULT" ] && [ -f "$ANDROID_DEFAULT/strings.xml" ]; then
  FOUND_ANY_SOURCE=1
  dump_xml_keys() {
    grep -oE '<(string|plurals|string-array)[^>]*name="[^"]+"' "$1" 2>/dev/null \
      | grep -oE 'name="[^"]+"' | sed -E 's/name="([^"]+)"/\1/' | sort -u
  }
  RES_DIR=$(dirname "$ANDROID_DEFAULT")
  for d in "$RES_DIR"/values-*; do
    [ -d "$d" ] && [ -f "$d/strings.xml" ] || continue
    suffix=$(basename "$d" | sed 's/^values-//')
    # only locale qualifiers (de, fr-rCA), skip night/w600dp etc.
    [[ "$suffix" =~ ^[a-z]{2}(-r[A-Z]{2})?$ ]] || continue
    gaps=$(comm -23 <(dump_xml_keys "$ANDROID_DEFAULT/strings.xml") <(dump_xml_keys "$d/strings.xml"))
    rev_gaps=$(comm -13 <(dump_xml_keys "$ANDROID_DEFAULT/strings.xml") <(dump_xml_keys "$d/strings.xml"))
    # translatable="false" keys legitimately exist only in default values/
    # (attribute order varies: name can come before or after translatable)
    nontranslatable=$(grep 'translatable="false"' "$ANDROID_DEFAULT/strings.xml" 2>/dev/null | grep -oE 'name="[^"]+"' | sed -E 's/name="([^"]+)"/\1/' || true)
    [ -n "$gaps" ] && while IFS= read -r k; do
      echo "$nontranslatable" | grep -qx "$k" && continue
      report "$suffix" "$k"
    done <<< "$gaps"
    [ -n "$rev_gaps" ] && while IFS= read -r k; do report "default" "$k (only in values-$suffix)"; done <<< "$rev_gaps"
  done
fi

# --- result -------------------------------------------------------------------
if [ "$FOUND_ANY_SOURCE" -eq 0 ]; then
  echo "I18N_RESULT=SKIP (no multi-locale translation source found)"
elif [ "$MISSING_COUNT" -gt 0 ]; then
  echo "I18N_RESULT=MISSING ($MISSING_COUNT gaps)"
else
  echo "I18N_RESULT=OK"
fi
