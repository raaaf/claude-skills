# Linters, Formatters, Static Analysis & Test Runner

Detection order: **Formatter → Linter → Static Analysis → Tests**. All via auto-detection; unknown stacks are skipped.

## PHP

| Detection signal | Command | Scope (audit) | 
|---|---|---|
| `composer.json` with `pint` dependency | `./vendor/bin/pint {CHANGED_PHP_FILES}` | Changed files |
| `.php-cs-fixer.php` | `./vendor/bin/php-cs-fixer fix {CHANGED_PHP_FILES}` | Changed files |
| `composer.json` with `phpcs` script | `composer phpcs:fix` | Changed files |
| `phpstan.neon` | `./vendor/bin/phpstan analyse` | **Always global** (type system doesn't respect file boundaries) |

**PHPCS — pre-existing errors:** ALWAYS fix all PHPCS errors, even in files we didn't directly change. CI checks the whole repo. Only warnings (not errors) can be ignored with `--runtime-set ignore_warnings_on_exit 1`.

## JavaScript / TypeScript / CSS

| Detection signal | Command | Scope (audit) |
|---|---|---|
| `eslint.config.*` or `.eslintrc*` | `npx eslint --fix {CHANGED_JS_FILES}` | Changed files |
| `.prettierrc*` or `prettier.config.*` | `npx prettier --write {CHANGED_JS_CSS_FILES}` | Changed files |
| `.stylelintrc*` | `npx stylelint --fix {CHANGED_CSS_FILES}` | Changed files |

## Native Mobile (iOS / Android / Flutter)

| Detection signal | Command | Scope (audit) |
|---|---|---|
| `.swiftlint.yml` | `swiftlint --fix {CHANGED_SWIFT_FILES}` then `swiftlint lint {FILES}` | Changed files |
| `.swiftformat` | `swiftformat {CHANGED_SWIFT_FILES}` | Changed files |
| `.editorconfig` + `*.kt` without detekt | `ktlint -F {CHANGED_KT_FILES}` (if installed) | Changed files |
| `detekt.yml` / `config/detekt` | `./gradlew detekt` | Global (Gradle task) |
| `pubspec.yaml` (Flutter) | `dart format {CHANGED_DART_FILES}` + `dart analyze` | format scoped, analyze global |

Tool not installed (`command -v` fails)? → skip with a note, do NOT install via brew/gem.

**xcodegen projects: regenerate after ANY wave that created a Swift file, test files included.** `*.xcodeproj` is rebuilt from the on-disk tree, so a file written after the last `xcodegen generate` is simply not in the target. There is no error: the build succeeds, the test run succeeds, and the new tests never ran. That is indistinguishable from "all green" in every line of output the orchestrator reads. So: after a fix wave that added files, run `xcodegen generate` BEFORE the test run, and confirm the reported test count rose by the number of cases the wave added. A wave that adds tests and reports an unchanged count did not run them (see `guidelines/native-mobile.md`, section IX).

**xcodegen: target-level `resources:` entries are silently ignored.** `project.yml` accepts a `resources:` key inside a `targets.<name>` block, xcodegen does not error on it, and it does not get wired into the generated `pbxproj` either — the asset (e.g. a privacy manifest, a `.xcassets` catalog) simply never lands in the build. There is no build failure to catch this: the project generates, the build succeeds, the missing resource just never gets copied. Resources belong in the top-level (project-wide) `resources:`/`settings:` structure or an explicit build phase, not nested under a target. When a fix wave adds or moves a resource entry in `project.yml`, do not trust that xcodegen picked it up because generation succeeded — grep the generated `.xcodeproj/project.pbxproj` for the resource's filename directly and confirm it appears in a `PBXResourcesBuildPhase`/`PBXBuildFile` entry for the intended target. A fix wave here ran a full round without effect until a later worker checked the generated pbxproj itself instead of trusting a clean `xcodegen generate` exit code.

For `/full-audit`, all linters/formatters run globally instead of file-scoped.

On static analysis errors: fix manually, re-run. Repeat until clean.

## Test Runner

**Core principle for /audit: only run relevant/affected tests locally. The full suite runs in CI on every push.** This is explicitly requested by the user and saves significant time on large test suites (2000+ tests).

### Determining Affected Tests

For each changed code file, the corresponding test file is looked up:

| Framework | Mapping |
|-----------|---------|
| Laravel/PHPUnit | `app/Foo/Bar.php` → `tests/**/BarTest.php` (grep for class name) |
| Vitest/Jest | `src/foo/bar.ts` → `src/foo/bar.{test,spec}.{ts,tsx,js,jsx}` or `__tests__/bar.test.*` |
| Pytest | `src/foo/bar.py` → `tests/**/test_bar.py` or `tests/**/bar_test.py` |
| XCTest/Swift Testing | `Sources/Foo/Bar.swift` → `Tests/**/BarTests.swift` |
| JUnit (Android) | `app/src/main/**/Bar.kt` → `app/src/test/**/BarTest.kt` |
| Flutter | `lib/foo/bar.dart` → `test/foo/bar_test.dart` |

Additionally: directly changed test files (`*Test.php`, `*.test.ts`, `test_*.py`) always run.

No affected tests found? → skip the test step, note in the audit log: `Tests: skipped (no affected tests — CI covers the full suite)`.

### Runner Invocations (affected files only)

| Detection signal | Command (diff-scoped) |
|---|---|
| `phpunit.xml` + Laravel | `php artisan test {AFFECTED_TEST_FILES}` |
| `phpunit.xml` (plain) | `./vendor/bin/phpunit {AFFECTED_TEST_FILES}` |
| `vitest.config.*` | `npx vitest run {AFFECTED_TEST_FILES}` |
| `jest.config.*` | `npx jest {AFFECTED_TEST_FILES}` |
| `pytest.ini` or `pyproject.toml` with pytest | `pytest {AFFECTED_TEST_FILES}` |
| `*.xcodeproj` / `Package.swift` | `xcodebuild test -only-testing:{TARGET}/{CLASS}` or `swift test --filter {CLASS}` |
| `build.gradle(.kts)` | `./gradlew test --tests "{CLASS}"` |
| `pubspec.yaml` (Flutter) | `flutter test {AFFECTED_TEST_FILES}` |
| `bun.lockb` / `bunfig.toml` (Bun) | `bun run test {AFFECTED_TEST_FILES}` — never bare `bun test`, see below |

**Do not use in /audit:** `composer test`, `npm test`, `npm run test` — these typically run the full suite. Call the runner directly with file arguments instead.

**Bun: `bun test` vs `bun run test` is not a stylistic choice.** Bun auto-loads `.env`, but only the `test` script defined in `package.json` carries the env vars that script sets inline or that CI/local convention puts there (e.g. `SV_DB_PATH=:memory:` to point tests at an isolated in-memory DB instead of the real one). Bare `bun test` skips the `package.json` script entirely and runs against whatever `.env` resolves to — real services, a real dev DB, live API keys. A fix agent that ran raw `bun test` after a security-focused live-probing session read the DB the probing had dirtied and produced a false diagnosis from it. Always invoke the `package.json` script (`bun run test`, or whatever it is named), never the bare `bun test` binary, and check `package.json` first if unsure which env vars the script sets.

**Test-run lock (MANDATORY for every test invocation — orchestrator, fix agents, verifiers):** wrap every runner call in `bash "$AUDIT_BIN/test-lock.sh" {command}` (e.g. `bash "$AUDIT_BIN/test-lock.sh" php artisan test {AFFECTED_TEST_FILES}`). Two agents running tests concurrently against the same DB corrupt each other's fixtures; the lock is a per-repo semaphore (mkdir spinlock, 15 min TTL, 16 min wait timeout — kept >= TTL so a waiter never times out before an actual orphan ages past the TTL), not a convention. Pass the absolute `AUDIT_BIN` path into every agent briefing that may run tests.

On failures: fix, re-run (only the affected tests, not the full suite). Repeat until green or clearly not auto-fixable. Add unfixable failures as **Critical**.

### /full-audit: Full Suite

For `/full-audit`, the complete test suite always runs (`composer test` / `npm test` / `pytest` / etc.). There, completeness matters more than runtime.
