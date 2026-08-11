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

### VI.a Resolve for the TARGET host's PHP, not the developer's

The base theme is free to run ahead of the client hosts. A fork is not: it inherits whatever the base last resolved, and that resolution followed the PHP of whoever ran `composer update`, not the PHP the client site runs.

Do all three, in this order:

1. **Set `config.platform.php` in `composer.json` to the client host's exact PHP version** before touching anything else:
   ```json
   "config": { "platform": { "php": "8.2.31" } }
   ```
   Without it Composer resolves against the developer's local PHP. On a machine running 8.5, a declared constraint of `^8.2` happily accepts packages requiring 8.4, because 8.4 satisfies `^8.2`. The lock then records `"platform": "^8.2"` while `vendor/composer/platform_check.php` enforces `>= 80401`, and the site fatals on the production host before a single line of theme code runs.

2. **Downgrade the inherited dependency majors to versions the target PHP supports.** Check every `require` and `require-dev` entry, not just the runtime ones. Concretely, at the time of writing: `illuminate/*` 13 and `symfony/*` 8 both require PHP 8.3+ or 8.4+; the 8.2-compatible line is `illuminate/*` 12 and `symfony/*` 7.

3. **Pin dev dependencies to versions the target PHP supports too.** This is the one that gets missed, because dev dependencies feel like they cannot reach production. They reach it two ways: a `composer install` that forgets `--no-dev` ships them, and `platform_check.php` is generated from everything actually installed. Exact pins are especially prone to this: `"symfony/process": "8.0.5.0"` looks locked down and safe, and requires PHP 8.4.

**Verification, and it must be run under the target PHP, not the dev PHP:**

```bash
composer validate --no-check-publish        # declaration self-consistent?
composer audit                              # read the WHOLE output, not the tail
grep -oE 'PHP_VERSION_ID >= [0-9]+' vendor/composer/platform_check.php
```

The `platform_check.php` number is the only one that decides whether the site boots. If it is higher than the host's PHP, the theme is undeployable regardless of what `composer.json` claims.

Two failures this rule comes from, both real: a starter whose `composer.json` declared `"php": "^8.3"` while requiring `symfony/translation: ^8.0`, a combination with no valid resolution for 8.3 at all; and five client themes declaring `"php": "^8.2"` whose exact-pinned dev dependencies had already drifted to Symfony 8, so `composer install` including dev could not be satisfied for their own production PHP.

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
grep -rnE '(^[[:space:]]*|>)\(\$[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\]|->[A-Za-z_][A-Za-z0-9_]*)*\)[[:space:]]*(<|$)' templates/
```

**Zero matches required.** Any hit is a stripped directive. (2026-06-11: 23 templates in goldene-strategie lost `@kses`; content was missing on every page of the live site and nothing in test/lint/build noticed.)

The pattern is deliberately narrow: it requires the parenthesised expression to be COMPLETE and in output position, meaning the line ends after the closing paren or continues with markup. That is what a stripped directive leaves behind. A multi-line PHP expression, by contrast, continues with an operator.

The earlier, looser version of this check (`'(^\s*|>)\(\$\w+'`) fired on every one of these six themes, twice each, on perfectly valid code:

```php
$hasVideo = ($source === 'external' && $video_id) ||
            ($source === 'wordpress' && $video) ||      // <- matched, and is fine
```

That matters more than it looks. A propagation gate that cries wolf on the first theme you run it against gets waved through on the second, and by the third nobody reads it. The check exists to stop a repeat of an incident that took three production sites down; a check that is routinely overridden protects nothing. Verified against all six themes: the narrow pattern reports zero, while still catching `($column_1)`, `($item['title'])` and `($obj->prop)`.

### 2a. Duplicate-attribute scan after every attribute-inserting replacement

The corruption scan above catches directives that lost their argument. It does not catch the opposite shape: a replacement that emits its own match twice. The usual cause is a capture group nested inside another one, where the replacement then references both:

```python
# WRONG — group 2 sits INSIDE group 1, so \1\2 repeats it
re.sub(r'(<x-link :url="[^"]*"((?: size="sm")?)) (class=)', r'\1\2 aria-hidden="true" \3', s)
# produces: <x-link :url="..." size="sm" size="sm" aria-hidden="true" class=...
```

```bash
grep -rPo '([a-z-]+="[^"]*") \1' templates/          # -P, NOT -E
# fallback where PCRE is unavailable:
find templates -name '*.blade.php' -exec perl -ne 'while (/([a-z-]+="[^"]*") \1/g) { print "$ARGV:$.: $1\n" }' {} +
```

`-P` is load-bearing. The pattern needs a backreference, and POSIX ERE has none: `grep -E` treats `\1` as an invalid escape, errors out, and prints nothing. Inside a `for theme in ...` loop with stderr redirected — the normal shape of a propagation check — that reads as "0 matches, clean" for every repo. Always prove a new grep against a deliberately broken fixture before trusting a zero from it; a check that cannot fail is worse than no check, because it is recorded as a passing verification. (2026-08-06: the `-E` form was run across six themes and reported clean, while the duplicates it was written to find were sitting in two files per theme.)

**Zero matches required.** This survives everything: HTML parsers silently drop the second copy, Blade compiles it, the render harness renders it, tests stay green, and the page looks correct. It only shows up in the diff, which is exactly what nobody reads line by line after a five-repo bulk edit. (2026-08-06: caught in `home.blade.php` and `index.blade.php` across all five client themes, in the same run that added the attributes.)

The general rule this is an instance of: **after a bulk regex edit, read one full diff hunk per distinct pattern you applied** — not one per file, but one per pattern. Verification that only counts occurrences ("2 card links per theme, correct") confirms the edit fired; it says nothing about what it produced.

### 3. Render verification

Greps catch the known corruption shapes. They do not catch a missing class, a renamed method, or a signature change. Run the theme's render smoke test (`tests/Unit/TemplateRenderTest.php` in these themes: compiles and renders every `templates/**/*.blade.php` against the bootstrap mocks) under the **production** PHP version, not the local dev version — "class not found" / "undefined method" are real errors, missing WP functions are mock gaps.

If a theme has no render harness, propagation is unverified regardless of green tests. Add the harness first.

## IX. Settled decisions (do not renegotiate per audit)

Audits kept rediscovering the same two things and arguing them out from scratch each time. Both are
decided. Report drift from them, not the decisions themselves.

### Flexible-layout duplication is accepted, with one exception

`templates/flexible/*.blade.php` repeat two blocks across layouts: the section-header block and the
image-card block. They are byte-identical and technically safe to extract — that was measured four
audits running (2026-03-27, 03-31, 06-11, 08-03), and the verdict swung open → accepted → fixed →
open again. The renegotiation itself is the defect, not any single answer.

**Decided:** the duplication stays until someone terminates it deliberately, as its own task with its
own propagation plan. An audit may note it once; it is not a finding.

**One exception, and it matters:** the grid wrapper's `gap` stays explicit per layout. `three-columns`
already differs from `two-columns` and `four-columns`, so a sweep that "harmonises" the wrappers would
silently change a rendered value in one of them. A consolidation that touches `gap` is a Critical
finding, not a cleanup.

### Propagation risk is the standing reason against sweeps

Five client themes are forked from `wordpress-starter-theme`. A regex sweep across all six repos has
already produced three production outages in one day (2026-06-11), and a follow-up sweep on
2026-08-06 shipped duplicate attributes into ten files while every test stayed green.

**Decided:** a sweep across the forks is never the default. Per-theme review, per-theme verification,
per-theme diff reading. When an audit weighs a refactor whose value is "less duplication across the
forks", this is the counterweight — cite this section instead of re-deriving the argument, and make the
recommendation only if the benefit clears it.
