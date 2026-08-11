#!/usr/bin/env bash
#
# check-outdated.sh — dependency health check, two independent parts:
#
#   SECURITY  known-vulnerable dependencies (audit databases). Push-blocking
#             material -> /audit runs this part when a manifest/lockfile is
#             in the diff; /full-audit always.
#   OUTDATED  stale majors/minors. Informational, reported as Minor. Runs in
#             /full-audit (always) and /audit (when a manifest/lockfile is in
#             the diff). --security-only suppresses it for callers that only
#             want the push-blocking part.
#
# Output:
#   DEP_SECURITY_RESULT=CLEAN | VULNS (N) | TIMEOUT | SKIP
#   DEP_OUTDATED_RESULT=CURRENT | OUTDATED (N) | TIMEOUT | SKIP   (omitted with --security-only)
#   plus the raw tool output between markers for the orchestrator to parse.
#
# Tools that are not installed are skipped with a note — NEVER installed here.
# Both parts need network; offline runs degrade to SKIP, not failure. A check
# that hangs or times out degrades to TIMEOUT, never silently to CLEAN/CURRENT
# — a timed-out check is unverified, not a confirmed all-clear.
#
# Every network call below runs through run_with_timeout() with a 60s bound
# (NET_TIMEOUT_SECS). macOS ships no timeout(1); GNU coreutils installs it as
# gtimeout. Preference order: timeout, then gtimeout, then unwrapped (fail
# open — a missing timeout binary must never turn a working check into a
# silent no-op).
#
# Usage: bash check-outdated.sh [PROJECT_ROOT] [--security-only]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MODE="${2:-full}"
cd "$ROOT"

VULN_COUNT=0
OUTDATED_COUNT=0
SEC_RAN=0
OUT_RAN=0
SEC_TIMEOUT=0
OUT_TIMEOUT=0

note() { echo "NOTE: $1"; }

# --- network timeout wrapper ---------------------------------------------------
NET_TIMEOUT_SECS=60
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

run_with_timeout() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$NET_TIMEOUT_SECS" "$@"
  else
    "$@"
  fi
}

# --- SECURITY -----------------------------------------------------------------
echo "---DEP-SECURITY---"

if [ -f "package.json" ] && command -v npm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_JSON=$(run_with_timeout npm audit --omit=dev --json 2>/dev/null)
  NPM_AUDIT_EXIT=$?
  if [ "$NPM_AUDIT_EXIT" -eq 124 ]; then
    SEC_TIMEOUT=1
    note "npm audit timed out after ${NET_TIMEOUT_SECS}s — security result may be incomplete"
  else
    N=$(echo "$AUDIT_JSON" | jq -r '(.metadata.vulnerabilities.high // 0) + (.metadata.vulnerabilities.critical // 0)' 2>/dev/null || echo 0)
    case "$N" in *[!0-9]*|"") N=0 ;; esac
    if [ "$N" -gt 0 ]; then
      VULN_COUNT=$((VULN_COUNT + N))
      echo "$AUDIT_JSON" | jq -r '.vulnerabilities | to_entries[] | select(.value.severity == "high" or .value.severity == "critical") | "\(.value.severity): \(.key)"' 2>/dev/null | head -20
    fi
  fi
fi

if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_OUT=$(run_with_timeout composer audit --no-interaction 2>&1)
  COMPOSER_AUDIT_EXIT=$?
  if [ "$COMPOSER_AUDIT_EXIT" -eq 124 ]; then
    SEC_TIMEOUT=1
    note "composer audit timed out after ${NET_TIMEOUT_SECS}s — security result may be incomplete"
  else
    N=$(echo "$AUDIT_OUT" | grep -ciE "CVE-|GHSA-" || true)
    case "$N" in *[!0-9]*|"") N=0 ;; esac
    if [ "$N" -gt 0 ]; then
      VULN_COUNT=$((VULN_COUNT + N))
      echo "$AUDIT_OUT" | head -30
    fi
  fi
fi

if { [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; } && command -v pip-audit >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_OUT=$(run_with_timeout pip-audit 2>&1)
  PIP_AUDIT_EXIT=$?
  if [ "$PIP_AUDIT_EXIT" -eq 124 ]; then
    SEC_TIMEOUT=1
    note "pip-audit timed out after ${NET_TIMEOUT_SECS}s — security result may be incomplete"
  else
    if echo "$AUDIT_OUT" | grep -qiE "found [1-9][0-9]* vulnerab"; then
      N=$(echo "$AUDIT_OUT" | grep -oiE "found [0-9]+" | grep -oE "[0-9]+" | head -1)
      VULN_COUNT=$((VULN_COUNT + ${N:-1}))
      echo "$AUDIT_OUT" | head -20
    fi
  fi
fi

if [ "$SEC_RAN" -eq 0 ]; then
  echo "DEP_SECURITY_RESULT=SKIP (no supported manifest or tool missing)"
elif [ "$VULN_COUNT" -gt 0 ]; then
  echo "DEP_SECURITY_RESULT=VULNS ($VULN_COUNT)"
elif [ "$SEC_TIMEOUT" -eq 1 ]; then
  echo "DEP_SECURITY_RESULT=TIMEOUT (network check did not complete within ${NET_TIMEOUT_SECS}s — not verified, not clean)"
else
  echo "DEP_SECURITY_RESULT=CLEAN"
fi

[ "$MODE" = "--security-only" ] && exit 0

# --- OUTDATED -------------------------------------------------------------------
echo "---DEP-OUTDATED---"

if [ -f "package.json" ] && command -v npm >/dev/null 2>&1; then
  OUT_RAN=1
  OUT=$(run_with_timeout npm outdated 2>/dev/null)
  NPM_OUTDATED_EXIT=$?
  if [ "$NPM_OUTDATED_EXIT" -eq 124 ]; then
    OUT_TIMEOUT=1
    note "npm outdated timed out after ${NET_TIMEOUT_SECS}s — outdated result may be incomplete"
  elif [ -n "$OUT" ] && [ "$(echo "$OUT" | wc -l)" -gt 1 ]; then
    N=$(($(echo "$OUT" | wc -l) - 1))
    OUTDATED_COUNT=$((OUTDATED_COUNT + N))
    echo "$OUT" | head -25
  fi
fi

if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
  OUT_RAN=1
  RAW=$(run_with_timeout composer outdated --direct --no-interaction 2>/dev/null)
  COMPOSER_OUTDATED_EXIT=$?
  if [ "$COMPOSER_OUTDATED_EXIT" -eq 124 ]; then
    OUT_TIMEOUT=1
    note "composer outdated timed out after ${NET_TIMEOUT_SECS}s — outdated result may be incomplete"
  else
    OUT=$(echo "$RAW" | grep -E "^[a-z0-9_.-]+/" || true)
    if [ -n "$OUT" ]; then
      N=$(echo "$OUT" | wc -l | tr -d ' ')
      OUTDATED_COUNT=$((OUTDATED_COUNT + N))
      echo "$OUT" | head -25
    fi
  fi
fi

if [ -f "Podfile" ] && command -v pod >/dev/null 2>&1; then
  OUT_RAN=1
  RAW=$(run_with_timeout pod outdated 2>/dev/null)
  POD_OUTDATED_EXIT=$?
  if [ "$POD_OUTDATED_EXIT" -eq 124 ]; then
    OUT_TIMEOUT=1
    note "pod outdated timed out after ${NET_TIMEOUT_SECS}s — outdated result may be incomplete"
  else
    OUT=$(echo "$RAW" | grep -E "^- " || true)
    if [ -n "$OUT" ]; then
      N=$(echo "$OUT" | wc -l | tr -d ' ')
      OUTDATED_COUNT=$((OUTDATED_COUNT + N))
      echo "$OUT" | head -25
    fi
  fi
fi

if [ -f "pubspec.yaml" ] && command -v flutter >/dev/null 2>&1; then
  OUT_RAN=1
  RAW=$(run_with_timeout flutter pub outdated 2>/dev/null)
  FLUTTER_OUTDATED_EXIT=$?
  if [ "$FLUTTER_OUTDATED_EXIT" -eq 124 ]; then
    OUT_TIMEOUT=1
    note "flutter pub outdated timed out after ${NET_TIMEOUT_SECS}s — outdated result may be incomplete"
  else
    OUT=$(echo "$RAW" | grep -E "^\S+\s+\*" || true)
    if [ -n "$OUT" ]; then
      N=$(echo "$OUT" | wc -l | tr -d ' ')
      OUTDATED_COUNT=$((OUTDATED_COUNT + N))
      echo "$OUT" | head -25
    fi
  fi
fi

# SPM has no built-in outdated command; Package.resolved drift is covered by
# the lockfile pre-check. Gradle needs the versions plugin -> skipped.
[ -f "Package.swift" ] && note "SPM: no native outdated check — review Package.resolved manually"
{ [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; } && note "Gradle: outdated check needs versions-plugin — skipped"

if [ "$OUT_RAN" -eq 0 ]; then
  echo "DEP_OUTDATED_RESULT=SKIP (no supported manifest or tool missing)"
elif [ "$OUTDATED_COUNT" -gt 0 ]; then
  echo "DEP_OUTDATED_RESULT=OUTDATED ($OUTDATED_COUNT)"
elif [ "$OUT_TIMEOUT" -eq 1 ]; then
  echo "DEP_OUTDATED_RESULT=TIMEOUT (network check did not complete within ${NET_TIMEOUT_SECS}s — not verified, not current)"
else
  echo "DEP_OUTDATED_RESULT=CURRENT"
fi
