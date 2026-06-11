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

# --- locate translation base dir ---------------------------------------------
BASE=""
for candidate in "$ROOT/resources/lang" "$ROOT/lang" "$ROOT/locales" "$ROOT/translations" "$ROOT/i18n"; do
  [ -d "$candidate" ] && { BASE="$candidate"; break; }
done

if [ -z "$BASE" ]; then
  echo "I18N_RESULT=SKIP (no translation directory found)"
  exit 0
fi

MISSING_COUNT=0
report() { echo "MISSING $1: $2"; MISSING_COUNT=$((MISSING_COUNT + 1)); }

# --- Mode A: per-locale subdirectories (Laravel) ------------------------------
LOCALE_DIRS=()
while IFS= read -r d; do
  name=$(basename "$d")
  # locale dirs are short: de, en, fr, de_DE, pt-BR, vendor excluded
  if [[ "$name" =~ ^[a-z]{2}([_-][A-Za-z]{2})?$ ]]; then
    LOCALE_DIRS+=("$d")
  fi
done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d | sort)

if [ "${#LOCALE_DIRS[@]}" -ge 2 ]; then
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
while IFS= read -r f; do
  name=$(basename "$f" .json)
  [[ "$name" =~ ^[a-z]{2}([_-][A-Za-z]{2})?$ ]] && JSON_FILES+=("$f")
done < <(find "$BASE" -maxdepth 1 -type f -name "*.json" | sort)

if [ "${#JSON_FILES[@]}" -ge 2 ] && command -v jq >/dev/null 2>&1; then
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

# --- result -------------------------------------------------------------------
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "I18N_RESULT=MISSING ($MISSING_COUNT gaps)"
else
  echo "I18N_RESULT=OK"
fi
