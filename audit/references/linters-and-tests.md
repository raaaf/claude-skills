# Linters, Formatters, Static Analysis & Test-Runner

Erkennungsreihenfolge: **Formatter → Linter → Static Analysis → Tests**. Alles per Auto-Detection; unbekannte Stacks überspringen.

## PHP

| Erkennungsmerkmal | Befehl | Scope (audit) |
|---|---|---|
| `composer.json` mit `pint`-Dependency | `./vendor/bin/pint {GEÄNDERTE_PHP_DATEIEN}` | Geänderte Dateien |
| `.php-cs-fixer.php` | `./vendor/bin/php-cs-fixer fix {GEÄNDERTE_PHP_DATEIEN}` | Geänderte Dateien |
| `composer.json` mit `phpcs`-Script | `composer phpcs:fix` | Geänderte Dateien |
| `phpstan.neon` | `./vendor/bin/phpstan analyse` | **Immer global** (Typsystem kennt keine Dateigrenze) |

**PHPCS — pre-existierende Fehler:** IMMER alle PHPCS-Fehler beheben, auch in Dateien die wir nicht direkt geändert haben. CI prüft das gesamte Repo. Nur Warnings (nicht Errors) können mit `--runtime-set ignore_warnings_on_exit 1` ignoriert werden.

## JavaScript / TypeScript / CSS

| Erkennungsmerkmal | Befehl | Scope (audit) |
|---|---|---|
| `eslint.config.*` oder `.eslintrc*` | `npx eslint --fix {GEÄNDERTE_JS_DATEIEN}` | Geänderte Dateien |
| `.prettierrc*` oder `prettier.config.*` | `npx prettier --write {GEÄNDERTE_JS_CSS_DATEIEN}` | Geänderte Dateien |
| `.stylelintrc*` | `npx stylelint --fix {GEÄNDERTE_CSS_DATEIEN}` | Geänderte Dateien |

## Native Mobile (iOS / Android / Flutter)

| Erkennungsmerkmal | Befehl | Scope (audit) |
|---|---|---|
| `.swiftlint.yml` | `swiftlint --fix {GEÄNDERTE_SWIFT_DATEIEN}` dann `swiftlint lint {DATEIEN}` | Geänderte Dateien |
| `.swiftformat` | `swiftformat {GEÄNDERTE_SWIFT_DATEIEN}` | Geänderte Dateien |
| `.editorconfig` + `*.kt` ohne detekt | `ktlint -F {GEÄNDERTE_KT_DATEIEN}` (falls installiert) | Geänderte Dateien |
| `detekt.yml` / `config/detekt` | `./gradlew detekt` | Global (Gradle-Task) |
| `pubspec.yaml` (Flutter) | `dart format {GEÄNDERTE_DART_DATEIEN}` + `dart analyze` | format scoped, analyze global |

Tool nicht installiert (`command -v` schlaegt fehl)? → ueberspringen mit Hinweis, NICHT via brew/gem installieren.

Für `/full-audit` werden alle Linter/Formatter global statt datei-scoped ausgeführt.

Bei Static-Analysis-Fehlern: manuell fixen, erneut laufen lassen. Wiederholen bis sauber.

## Test-Runner

**Grundprinzip fuer /audit: Nur relevante/betroffene Tests lokal ausfuehren. Die volle Suite laeuft in CI bei jedem Push.** Das ist explizit so vom User gewuenscht und spart massiv Zeit bei grossen Test-Suiten (2000+ Tests).

### Betroffene Tests ermitteln

Pro geaenderter Code-Datei wird die zugehoerige Test-Datei gesucht:

| Framework | Mapping |
|-----------|---------|
| Laravel/PHPUnit | `app/Foo/Bar.php` → `tests/**/BarTest.php` (grep nach Klassennamen) |
| Vitest/Jest | `src/foo/bar.ts` → `src/foo/bar.{test,spec}.{ts,tsx,js,jsx}` oder `__tests__/bar.test.*` |
| Pytest | `src/foo/bar.py` → `tests/**/test_bar.py` oder `tests/**/bar_test.py` |
| XCTest/Swift Testing | `Sources/Foo/Bar.swift` → `Tests/**/BarTests.swift` |
| JUnit (Android) | `app/src/main/**/Bar.kt` → `app/src/test/**/BarTest.kt` |
| Flutter | `lib/foo/bar.dart` → `test/foo/bar_test.dart` |

Zusaetzlich: direkt geaenderte Test-Dateien (`*Test.php`, `*.test.ts`, `test_*.py`) laufen immer mit.

Keine betroffenen Tests gefunden? → Test-Step ueberspringen, Hinweis im Audit-Log: `Tests: uebersprungen (keine betroffenen Tests — CI deckt volle Suite ab)`.

### Runner-Aufrufe (nur betroffene Dateien)

| Erkennungsmerkmal | Befehl (diff-scoped) |
|---|---|
| `phpunit.xml` + Laravel | `php artisan test {BETROFFENE_TEST_DATEIEN}` |
| `phpunit.xml` (pur) | `./vendor/bin/phpunit {BETROFFENE_TEST_DATEIEN}` |
| `vitest.config.*` | `npx vitest run {BETROFFENE_TEST_DATEIEN}` |
| `jest.config.*` | `npx jest {BETROFFENE_TEST_DATEIEN}` |
| `pytest.ini` oder `pyproject.toml` mit pytest | `pytest {BETROFFENE_TEST_DATEIEN}` |
| `*.xcodeproj` / `Package.swift` | `xcodebuild test -only-testing:{TARGET}/{KLASSE}` bzw. `swift test --filter {KLASSE}` |
| `build.gradle(.kts)` | `./gradlew test --tests "{KLASSE}"` |
| `pubspec.yaml` (Flutter) | `flutter test {BETROFFENE_TEST_DATEIEN}` |

**Nicht nutzen in /audit:** `composer test`, `npm test`, `npm run test` — diese fuehren typischerweise die volle Suite aus. Stattdessen Runner direkt mit Datei-Argumenten aufrufen.

Bei Failures: fixen, erneut laufen lassen (nur die betroffenen Tests, nicht die volle Suite). Wiederholen bis gruen oder klar nicht automatisch fixbar. Unfixbare Failures als **Critical** aufnehmen.

### /full-audit: volle Suite

Fuer `/full-audit` laeuft immer die komplette Test-Suite (`composer test` / `npm test` / `pytest` / etc.). Dort ist Vollstaendigkeit wichtiger als Laufzeit.
