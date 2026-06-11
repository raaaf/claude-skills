#!/usr/bin/env bash
#
# check-outdated.sh — dependency health check, two independent parts:
#
#   SECURITY  known-vulnerable dependencies (audit databases). Push-blocking
#             material -> /audit runs this part when a manifest/lockfile is
#             in the diff; /full-audit always.
#   OUTDATED  stale majors/minors. Informational -> /full-audit only,
#             reported as Minor. Never run on pre-push (noise).
#
# Output:
#   DEP_SECURITY_RESULT=CLEAN | VULNS (N) | SKIP
#   DEP_OUTDATED_RESULT=CURRENT | OUTDATED (N) | SKIP   (omitted with --security-only)
#   plus the raw tool output between markers for the orchestrator to parse.
#
# Tools that are not installed are skipped with a note — NEVER installed here.
# Both parts need network; offline runs degrade to SKIP, not failure.
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

note() { echo "NOTE: $1"; }

# --- SECURITY -----------------------------------------------------------------
echo "---DEP-SECURITY---"

if [ -f "package.json" ] && command -v npm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_JSON=$(npm audit --omit=dev --json 2>/dev/null || true)
  N=$(echo "$AUDIT_JSON" | jq -r '(.metadata.vulnerabilities.high // 0) + (.metadata.vulnerabilities.critical // 0)' 2>/dev/null || echo 0)
  case "$N" in *[!0-9]*|"") N=0 ;; esac
  if [ "$N" -gt 0 ]; then
    VULN_COUNT=$((VULN_COUNT + N))
    echo "$AUDIT_JSON" | jq -r '.vulnerabilities | to_entries[] | select(.value.severity == "high" or .value.severity == "critical") | "\(.value.severity): \(.key)"' 2>/dev/null | head -20
  fi
fi

if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_OUT=$(composer audit --no-interaction 2>&1 || true)
  N=$(echo "$AUDIT_OUT" | grep -ciE "CVE-|GHSA-" || true)
  case "$N" in *[!0-9]*|"") N=0 ;; esac
  if [ "$N" -gt 0 ]; then
    VULN_COUNT=$((VULN_COUNT + N))
    echo "$AUDIT_OUT" | head -30
  fi
fi

if { [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; } && command -v pip-audit >/dev/null 2>&1; then
  SEC_RAN=1
  AUDIT_OUT=$(pip-audit 2>&1 || true)
  if echo "$AUDIT_OUT" | grep -qiE "found [1-9][0-9]* vulnerab"; then
    N=$(echo "$AUDIT_OUT" | grep -oiE "found [0-9]+" | grep -oE "[0-9]+" | head -1)
    VULN_COUNT=$((VULN_COUNT + ${N:-1}))
    echo "$AUDIT_OUT" | head -20
  fi
fi

if [ "$SEC_RAN" -eq 0 ]; then
  echo "DEP_SECURITY_RESULT=SKIP (no supported manifest or tool missing)"
elif [ "$VULN_COUNT" -gt 0 ]; then
  echo "DEP_SECURITY_RESULT=VULNS ($VULN_COUNT)"
else
  echo "DEP_SECURITY_RESULT=CLEAN"
fi

[ "$MODE" = "--security-only" ] && exit 0

# --- OUTDATED -------------------------------------------------------------------
echo "---DEP-OUTDATED---"

if [ -f "package.json" ] && command -v npm >/dev/null 2>&1; then
  OUT_RAN=1
  OUT=$(npm outdated 2>/dev/null || true)
  if [ -n "$OUT" ] && [ "$(echo "$OUT" | wc -l)" -gt 1 ]; then
    N=$(($(echo "$OUT" | wc -l) - 1))
    OUTDATED_COUNT=$((OUTDATED_COUNT + N))
    echo "$OUT" | head -25
  fi
fi

if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
  OUT_RAN=1
  OUT=$(composer outdated --direct --no-interaction 2>/dev/null | grep -E "^[a-z0-9_.-]+/" || true)
  if [ -n "$OUT" ]; then
    N=$(echo "$OUT" | wc -l | tr -d ' ')
    OUTDATED_COUNT=$((OUTDATED_COUNT + N))
    echo "$OUT" | head -25
  fi
fi

if [ -f "Podfile" ] && command -v pod >/dev/null 2>&1; then
  OUT_RAN=1
  OUT=$(pod outdated 2>/dev/null | grep -E "^- " || true)
  if [ -n "$OUT" ]; then
    N=$(echo "$OUT" | wc -l | tr -d ' ')
    OUTDATED_COUNT=$((OUTDATED_COUNT + N))
    echo "$OUT" | head -25
  fi
fi

if [ -f "pubspec.yaml" ] && command -v flutter >/dev/null 2>&1; then
  OUT_RAN=1
  OUT=$(flutter pub outdated 2>/dev/null | grep -E "^\S+\s+\*" || true)
  if [ -n "$OUT" ]; then
    N=$(echo "$OUT" | wc -l | tr -d ' ')
    OUTDATED_COUNT=$((OUTDATED_COUNT + N))
    echo "$OUT" | head -25
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
else
  echo "DEP_OUTDATED_RESULT=CURRENT"
fi
