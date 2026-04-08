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

Für `/full-audit` werden alle Linter/Formatter global statt datei-scoped ausgeführt.

Bei Static-Analysis-Fehlern: manuell fixen, erneut laufen lassen. Wiederholen bis sauber.

## Test-Runner

| Erkennungsmerkmal | Befehl |
|---|---|
| `composer.json` mit `test`-Script | `composer test` |
| `package.json` mit `test`-Script | `npm test` |
| `phpunit.xml` (ohne Composer-Script) | `php artisan test` oder `./vendor/bin/phpunit` |
| `vitest.config.*` | `npx vitest run` |
| `jest.config.*` | `npx jest` |
| `pytest.ini` oder `pyproject.toml` mit pytest | `pytest` |

Alle erkannten Runner ausführen. Bei Failures: fixen, erneut laufen lassen. Wiederholen bis grün oder klar nicht automatisch fixbar. Unfixbare Failures als **Critical** aufnehmen.
