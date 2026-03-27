# Theme Fork Checklist

When forking `wordpress-starter-theme` (or any base theme) to create a new client theme, every item below must be updated before the first commit. The architecture subagent checks these during audits.

## I. Namespace & Autoloading

- `composer.json`: Update `autoload.psr-4` namespace from `WordpressStarter\` to the new namespace (e.g. `FIMVertrieb\`)
- Every PHP file in `src/`: Update `namespace` declarations
- Every Blade template with `@php use ...`: Update use statements to new namespace

## II. Text Domain & Theme Identity

- `style.css`: Theme Name, Theme URI, Description, Text Domain
- `package.json`: `name`, `text_domain`, `theme_uri`, `repository.url`
- `composer.json`: `name`, `description`, `license` (set to `proprietary` for client themes)
- `config/app.php`: Theme name constant

## III. GitHub & Update URLs

- `src/Providers/ThemeUpdateProvider.php`: GitHub repository URL (e.g. `raaaf/fim-vertrieb`)
- `package.json`: `repository.url`
- `composer.json`: `homepage` or `support.source`

## IV. Logging & Debug Prefixes

- `src/Providers/LogServiceProvider.php`: Log prefix must match new text domain

## V. Tests & Mocks

- `tests/bootstrap.php`: Mock template directory name
- `tests/Support/WordPressMocks.php`: Mock stylesheet URI
- `tests/Unit/ThemeContextTest.php`: All assertions referencing theme name/prefix
- Run `composer test` to verify all tests pass with new identifiers

## VI. Dependencies

- `composer.json`: Pin all dependency versions (no `*` or `dev-master`)
- Remove starter-specific dev dependencies not needed in the client theme

## VII. Quick Grep Verification

After updating, run these greps to catch stragglers:

```bash
# Replace OLD_NAMESPACE and OLD_TEXTDOMAIN with the starter values
grep -r "WordpressStarter" src/ templates/ tests/ config/ --include="*.php" --include="*.blade.php"
grep -r "wp-starter" . --include="*.php" --include="*.json" --include="*.css" --exclude-dir=vendor --exclude-dir=node_modules
grep -r "wordpress-starter-theme" . --include="*.php" --include="*.json" --include="*.md" --exclude-dir=vendor --exclude-dir=node_modules
```

Zero matches = ready to commit.
