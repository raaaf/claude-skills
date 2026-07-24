#!/usr/bin/env bash
#
# Deterministic baseline scan. Emits one line per check:
#   D<n>|<check-id>|PASS|<evidence>
#   D<n>|<check-id>|FAIL|<what is missing>
#   D<n>|<check-id>|UNVERIFIED|<why it needs LLM/manual judgment>
#
# Dimensions follow guidelines/baseline-spec.md. This script only asserts what
# can be decided from files; everything judgment-based stays UNVERIFIED.
#
# Usage: bash baseline-scan.sh [PROJECT_ROOT]
# bash 3.2 compatible (macOS default).
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

emit() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }

# Platform via the audit toolchain when reachable, else generic.
PLATFORM="web"
DETECT=""
for cand in \
  "$(dirname "$0")/../../audit/bin/detect-framework.sh" \
  "$HOME/.claude/skills/audit/bin/detect-framework.sh"; do
  [ -f "$cand" ] && DETECT="$cand" && break
done
if [ -n "$DETECT" ]; then
  eval "$(bash "$DETECT" "$ROOT" 2>/dev/null | grep -E '^(PLATFORM|FRAMEWORK)=' || true)"
fi
emit "D0" "platform" "PASS" "PLATFORM=${PLATFORM} FRAMEWORK=${FRAMEWORK:-generic}"

# ---------- D1 Positioning charter ----------
BASELINE_FILE=""
for f in BASELINE.md docs/BASELINE.md .claude/BASELINE.md; do
  [ -f "$f" ] && BASELINE_FILE="$f" && break
done
if [ -n "$BASELINE_FILE" ]; then
  emit "D1" "charter_file" "PASS" "$BASELINE_FILE"
  for section in "Keywords" "Value" "Target"; do
    if grep -qi "$section" "$BASELINE_FILE"; then
      emit "D1" "charter_$(echo "$section" | tr 'A-Z' 'a-z')" "PASS" "section present"
    else
      emit "D1" "charter_$(echo "$section" | tr 'A-Z' 'a-z')" "FAIL" "no '$section' section in $BASELINE_FILE"
    fi
  done
else
  emit "D1" "charter_file" "FAIL" "no BASELINE.md (root, docs/, .claude/)"
fi

# ---------- D2 Design foundation ----------
TOKEN_SIGNAL=""
[ -f "tailwind.config.js" ] || [ -f "tailwind.config.ts" ] && TOKEN_SIGNAL="tailwind config"
[ -z "$TOKEN_SIGNAL" ] && grep -rl --include='*.css' -m1 -- '--' resources src app assets styles css public 2>/dev/null | head -1 | grep -q . \
  && TOKEN_SIGNAL="CSS custom properties"
[ -z "$TOKEN_SIGNAL" ] && find . -maxdepth 4 \( -name 'tokens*' -o -name 'theme*' -o -name '*Theme*.swift' -o -name '*Theme*.kt' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1 | grep -q . \
  && TOKEN_SIGNAL="theme/token file"
if [ -n "$TOKEN_SIGNAL" ]; then
  emit "D2" "token_layer" "PASS" "$TOKEN_SIGNAL"
else
  emit "D2" "token_layer" "UNVERIFIED" "no obvious token layer; needs LLM look"
fi
emit "D2" "coverage" "UNVERIFIED" "token coverage and dark mode: delegated to /full-audit dim 7/8"

# ---------- D3 Accessibility process ----------
A11Y_SIGNAL=""
grep -rqiE 'axe|pa11y|lighthouse' .github/workflows 2>/dev/null && A11Y_SIGNAL="CI workflow"
[ -z "$A11Y_SIGNAL" ] && [ -f package.json ] && grep -qiE '"(axe-core|@axe-core|pa11y|lighthouse)' package.json && A11Y_SIGNAL="package.json"
if [ -n "$A11Y_SIGNAL" ]; then
  emit "D3" "a11y_tooling" "PASS" "$A11Y_SIGNAL"
else
  emit "D3" "a11y_tooling" "FAIL" "no axe/pa11y/lighthouse wired in CI or deps"
fi
if [ -n "$BASELINE_FILE" ] && grep -qiE 'voiceover|talkback|keyboard|screen ?reader' "$BASELINE_FILE"; then
  emit "D3" "manual_pass" "PASS" "noted in $BASELINE_FILE"
else
  emit "D3" "manual_pass" "FAIL" "no manual a11y pass documented"
fi

# ---------- D4 Quality gates ----------
TEST_SIGNAL=""
for f in vitest.config.ts vitest.config.js jest.config.js jest.config.ts phpunit.xml phpunit.xml.dist pytest.ini setup.cfg Package.swift; do
  [ -f "$f" ] && TEST_SIGNAL="$f" && break
done
[ -z "$TEST_SIGNAL" ] && [ -f package.json ] && grep -q '"test"' package.json && TEST_SIGNAL="package.json test script"
[ -z "$TEST_SIGNAL" ] && find . -maxdepth 3 -type d \( -name '*Tests' -o -name '__tests__' -o -name 'tests' -o -name 'test' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null | head -1 | grep -q . && TEST_SIGNAL="test directory"
if [ -n "$TEST_SIGNAL" ]; then
  emit "D4" "test_suite" "PASS" "$TEST_SIGNAL"
else
  emit "D4" "test_suite" "FAIL" "no test config, script, or test directory"
fi
CI_FILE=""
if [ -d ".github/workflows" ]; then
  CI_FILE="$(grep -rliE 'test|lint' .github/workflows 2>/dev/null | head -1 || true)"
fi
if [ -n "$CI_FILE" ]; then
  emit "D4" "ci_gate" "PASS" "$CI_FILE"
else
  emit "D4" "ci_gate" "FAIL" "no CI workflow running tests/lint"
fi
if [ -f ".husky/pre-push" ] || [ -f ".git/hooks/pre-push" ] || grep -q 'claude-audit-passed' "$HOME/.claude/settings.json" 2>/dev/null; then
  emit "D4" "pre_push_gate" "PASS" "local pre-push gate present"
else
  emit "D4" "pre_push_gate" "FAIL" "no local pre-push gate"
fi
emit "D4" "branch_protection" "UNVERIFIED" "check via: gh api repos/{owner}/{repo}/branches/{main}/protection"
emit "D4" "critical_paths" "UNVERIFIED" "whether core-loop paths are tested needs LLM look"

# ---------- D5 Security posture ----------
if [ -f ".gitignore" ] && grep -qE '(^|/)\.env' .gitignore; then
  emit "D5" "env_ignored" "PASS" ".gitignore covers .env"
else
  emit "D5" "env_ignored" "FAIL" ".env not covered by .gitignore"
fi
TRACKED_ENV="$(git ls-files 2>/dev/null | grep -E '(^|/)\.env$|(^|/)\.env\.[a-z]+$' | grep -v '\.example$' | head -3 || true)"
if [ -n "$TRACKED_ENV" ]; then
  emit "D5" "env_tracked" "FAIL" "env file(s) tracked in git: $(echo "$TRACKED_ENV" | tr '\n' ' ')"
else
  emit "D5" "env_tracked" "PASS" "no env files tracked"
fi
LOCK_SIGNAL=""
for f in package-lock.json pnpm-lock.yaml yarn.lock composer.lock Podfile.lock Package.resolved Gemfile.lock uv.lock poetry.lock; do
  [ -f "$f" ] && LOCK_SIGNAL="$f" && break
done
if [ -n "$LOCK_SIGNAL" ]; then
  emit "D5" "lockfile" "PASS" "$LOCK_SIGNAL"
else
  emit "D5" "lockfile" "UNVERIFIED" "no lockfile found (may be dependency-free)"
fi
emit "D5" "secret_scan" "UNVERIFIED" "run audit secret pass or gitleaks; never reproduce values"
emit "D5" "vuln_scan" "UNVERIFIED" "run: bash audit/bin/check-outdated.sh . --security-only"

# ---------- D6 Deployment and release ----------
DEPLOY_SIGNAL=""
grep -rliE 'deploy|release' .github/workflows 2>/dev/null | head -1 | grep -q . && DEPLOY_SIGNAL="CI deploy workflow"
[ -z "$DEPLOY_SIGNAL" ] && [ -f "fastlane/Fastfile" ] && DEPLOY_SIGNAL="fastlane/Fastfile"
[ -z "$DEPLOY_SIGNAL" ] && { [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "compose.yaml" ]; } && DEPLOY_SIGNAL="container config"
[ -z "$DEPLOY_SIGNAL" ] && find . -maxdepth 2 -name 'deploy*.sh' -not -path '*/node_modules/*' 2>/dev/null | head -1 | grep -q . && DEPLOY_SIGNAL="deploy script"
if [ -n "$DEPLOY_SIGNAL" ]; then
  emit "D6" "deploy_automation" "PASS" "$DEPLOY_SIGNAL"
else
  emit "D6" "deploy_automation" "FAIL" "no deploy workflow, Fastfile, container config, or deploy script"
fi
if { [ -n "$BASELINE_FILE" ] && grep -qi 'rollback' "$BASELINE_FILE"; } || grep -qi 'rollback' README.md 2>/dev/null; then
  emit "D6" "rollback_doc" "PASS" "rollback documented"
else
  emit "D6" "rollback_doc" "FAIL" "no rollback path documented (BASELINE.md/README)"
fi
emit "D6" "staging" "UNVERIFIED" "staging target existence needs config/LLM look"

# ---------- D7 Dependency currency ----------
emit "D7" "runtime_eol" "UNVERIFIED" "compare engine/runtime version against EOL tables"
emit "D7" "outdated" "UNVERIFIED" "run: bash audit/bin/check-outdated.sh ."

# ---------- D8 Backups and restore ----------
BACKUP_SIGNAL=""
find . -maxdepth 3 \( -name '*backup*' -o -name '*Backup*' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null | head -1 | grep -q . && BACKUP_SIGNAL="backup file/script"
[ -z "$BACKUP_SIGNAL" ] && [ -n "$BASELINE_FILE" ] && grep -qi 'backup' "$BASELINE_FILE" && BACKUP_SIGNAL="documented in $BASELINE_FILE"
if [ -n "$BACKUP_SIGNAL" ]; then
  emit "D8" "backup_mechanism" "PASS" "$BACKUP_SIGNAL"
else
  emit "D8" "backup_mechanism" "FAIL" "no backup script/config/doc found"
fi
if [ -n "$BASELINE_FILE" ] && grep -qiE 'restore.*(test|getestet|[0-9]{4})' "$BASELINE_FILE"; then
  emit "D8" "restore_tested" "PASS" "restore test noted in $BASELINE_FILE"
else
  emit "D8" "restore_tested" "FAIL" "no restore test documented (no note = failed, spec D8)"
fi

# ---------- D9 Observability ----------
OBS_SIGNAL=""
[ -f package.json ] && grep -qiE '"@sentry/|"posthog|"bugsnag' package.json && OBS_SIGNAL="package.json"
[ -z "$OBS_SIGNAL" ] && [ -f composer.json ] && grep -qi 'sentry' composer.json && OBS_SIGNAL="composer.json"
[ -z "$OBS_SIGNAL" ] && { [ -f Podfile ] || [ -f Package.swift ]; } && grep -qiE 'sentry|crashlytics|firebase' Podfile Package.swift 2>/dev/null && OBS_SIGNAL="iOS deps"
[ -z "$OBS_SIGNAL" ] && [ -f pubspec.yaml ] && grep -qiE 'sentry|crashlytics' pubspec.yaml && OBS_SIGNAL="pubspec.yaml"
if [ -n "$OBS_SIGNAL" ]; then
  emit "D9" "error_tracking" "PASS" "$OBS_SIGNAL"
else
  emit "D9" "error_tracking" "FAIL" "no error-tracking SDK in dependencies"
fi
emit "D9" "uptime_monitoring" "UNVERIFIED" "external service; check BASELINE.md ops section or ask"

# ---------- D10 Legal and privacy ----------
if [ "$PLATFORM" = "web" ]; then
  LEGAL_SIGNAL="$(grep -rliE 'impressum' --include='*.html' --include='*.php' --include='*.vue' --include='*.tsx' --include='*.jsx' --include='*.blade.php' . 2>/dev/null | grep -v node_modules | grep -v vendor | head -1 || true)"
  if [ -n "$LEGAL_SIGNAL" ]; then
    emit "D10" "impressum" "PASS" "$LEGAL_SIGNAL"
  else
    emit "D10" "impressum" "FAIL" "no Impressum page found"
  fi
  DS_SIGNAL="$(grep -rliE 'datenschutz|privacy' --include='*.html' --include='*.php' --include='*.vue' --include='*.tsx' --include='*.jsx' --include='*.blade.php' . 2>/dev/null | grep -v node_modules | grep -v vendor | head -1 || true)"
  if [ -n "$DS_SIGNAL" ]; then
    emit "D10" "datenschutz" "PASS" "$DS_SIGNAL"
  else
    emit "D10" "datenschutz" "FAIL" "no Datenschutz/privacy page found"
  fi
else
  emit "D10" "legal_links" "UNVERIFIED" "in-app legal links + store privacy labels need LLM/manual look"
fi

# ---------- D11 Documentation ----------
if [ -f "README.md" ]; then
  emit "D11" "readme" "PASS" "README.md"
  MISSING=""
  grep -qiE 'install|setup|getting started|run' README.md || MISSING="$MISSING run/setup"
  grep -qiE 'test' README.md || MISSING="$MISSING test"
  grep -qiE 'deploy|release' README.md || MISSING="$MISSING deploy"
  if [ -z "$MISSING" ]; then
    emit "D11" "readme_sections" "PASS" "run/test/deploy covered"
  else
    emit "D11" "readme_sections" "FAIL" "README missing:$MISSING"
  fi
else
  emit "D11" "readme" "FAIL" "no README.md"
fi

# ---------- D12 Environments and data ----------
if [ -f ".env.example" ] || [ -f ".env.dist" ]; then
  emit "D12" "env_example" "PASS" "env shape documented"
else
  if git ls-files 2>/dev/null | grep -q '\.env' || grep -rq 'process\.env\|getenv\|ENV\[' --include='*.ts' --include='*.js' --include='*.php' src app config 2>/dev/null; then
    emit "D12" "env_example" "FAIL" "env vars used but no .env.example"
  else
    emit "D12" "env_example" "UNVERIFIED" "no env usage detected (may not need one)"
  fi
fi
MIG_DIR="$(find . -maxdepth 3 -type d -name 'migrations' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null | head -1 || true)"
if [ -n "$MIG_DIR" ]; then
  emit "D12" "migrations" "PASS" "$MIG_DIR"
else
  emit "D12" "migrations" "UNVERIFIED" "no migrations dir (fine if no database)"
fi

exit 0
