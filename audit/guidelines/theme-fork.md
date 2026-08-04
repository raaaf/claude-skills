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

## VIII. Propagation Playbook (backporting base-theme changes into existing client themes)

Propagation is not forking. The client theme already exists, already has its own namespace — and the change arrives as an edit applied across N repos at once, usually by an agent, usually in parallel, usually verified only by `test`/`lint`/`build`. That verification does not render a single template, so the two failure modes below ship silently to production.

Both checks are MANDATORY after every propagation run, per theme, before commit.

### 1. Namespace adaptation check

A file copied from the base theme carries the base namespace in its `use` statements and its fully-qualified references. `composer test` passes because unit tests do not render Blade; the fatal only appears on the render path in production.

```bash
grep -rn "WordpressStarter" templates/ src/ config/
```

**Zero matches required outside `*.md`.** Any hit is an unadapted reference and a guaranteed fatal on every page that renders that template. (2026-06-11: `section.blade.php` referencing `\WordpressStarter\Acf\Fields` took stiftungs-navigator down entirely — empty 200s on every frontend request. `use WordpressStarter\PostTypes\*` did the same to moenius on any page using team/testimonials layouts.)

### 2. Corruption scan after every bulk replacement

A regex replacement across templates can strip the directive and leave its argument behind as bare text. `@kses($column_1)` becomes `($column_1)`, which renders as the literal string `($column_1)` — no error, no failing test, just missing content everywhere.

```bash
grep -rnE '(^\s*|>)\(\$\w+' templates/
```

**Zero matches required.** Any hit is a stripped directive. (2026-06-11: 23 templates in goldene-strategie lost `@kses`; content was missing on every page of the live site and nothing in test/lint/build noticed.)

### 3. Render verification

Greps catch the two known corruption shapes. They do not catch a missing class, a renamed method, or a signature change. Run the theme's render smoke test (`tests/Unit/TemplateRenderTest.php` in these themes: compiles and renders every `templates/**/*.blade.php` against the bootstrap mocks) under the **production** PHP version, not the local dev version — "class not found" / "undefined method" are real errors, missing WP functions are mock gaps.

If a theme has no render harness, propagation is unverified regardless of green tests. Add the harness first.
