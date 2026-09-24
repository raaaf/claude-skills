# Web Driver (Playwright)

Invoked by `/screens` `SKILL.md` Phase 5's driver step (plan step 5) when `.screens/config.json` has
a `web` platform and `screens/templates/capture.spec.ts` has been scaffolded into
`<project>/.screens/web/capture.spec.ts` (Phase 2 scaffold, "Per-project files" table).

## Invocation

From the target project root, after `screens.mjs up --platform web` reported `UP_RESULT=OK`:

```
cd <project root>
npx playwright test .screens/web/capture.spec.ts --workers=4 [--grep <pattern>]
```

`--grep <pattern>` narrows the run to the entry ids `screens.mjs plan`'s `PLAN_ENTRY <id>
{new|stale|missing_png}` lines named (skip `unchanged` ids); omit the flag on a first run or
`--full` (every entry is already planned). Build the pattern as an alternation of entry ids anchored
at the test name's start (test names are `${entry.id} ${state} ${role} ${viewport} ${theme}`, see
below), e.g. `--grep "^(dashboard|clients) "`.

The spec reads `.screens/config.json` and `.screens/manifest.json` from `process.cwd()` at
test-collection time, not per-project templating, so the same `screens/templates/capture.spec.ts`
file works unmodified for every Laravel/web pilot (repo `CLAUDE.md` "Reviewer: every generated
driver must read the manifest at runtime instead of hard-coding entries").

## What the spec does

- One Playwright `test()` per entry x state x role x viewport x theme (states/roles/viewports/themes
  default to `['filled']`/`['guest']`/`config.axes.viewports.web`/`config.axes.themes` when an entry
  omits them).
- `page.clock.setFixedTime('2026-05-12T09:41:00+02:00')` before navigation (topf-secret's
  `-ScreensFixedDate` convention, web equivalent).
- A CSS override disables all animations/transitions (`animation-duration`/`transition-duration:
  0s !important`).
- `context.route('**/*', ...)` allows only `localhost`/`127.0.0.1` requests, aborts everything else
  (no live third-party calls from a demo run; plan's "Dynamic content" edge case).
- Login: `role: "guest"` skips login; any other role posts `config.demo_logins[role]` /
  `config.demo_password` through `/login` (`input[name=email]`, `input[name=password]`, `button[type=submit]`),
  then `waitForLoadState('networkidle')`.
- Navigation: `page.goto(BASE_URL + entry.reach)`, `waitForLoadState('networkidle')`, then
  `entry.ready` (a CSS selector) via `waitForSelector` if set.
- `entry.mask` selectors are hidden (`visibility: hidden`) before the screenshot.
- Output: `.screens/.incoming/web/<entryId>__<state>__<role>__<viewport>__<theme>.png`, `fullPage:
  true`, matching the filename shape `screens.mjs promote` parses (`<entryId>__<rest>.png`).

## Server-side fixed clock (PHP projects, added after stage (b) STOP 2)

`page.clock.setFixedTime` only fakes the browser's `Date`; a Laravel dashboard's own aggregation
queries call PHP's `now()` server-side, which drifts between two capture runs and broke byte-hash
determinism (a real dashboard KPI changed between run 2a and run 2b on `apps/zeit/app`). Fix:

- `screens/templates/php/fixed-clock.php` is instantiated verbatim into `<project>/.screens/web/fixed-clock.php`
  by the Phase 2 scaffold (no project source file changes); it calls `Carbon::setTestNow()` when
  `SCREENS_FIXED_NOW` is set, otherwise it is a no-op.
- `screens/templates/php/zz-screens.ini` is instantiated into `<project>/.screens/web/php/zz-screens.ini`
  with `{{PROJECT_ROOT}}` replaced by the pilot's absolute path; it sets `auto_prepend_file` to the
  fixed-clock file above.
- `screens.mjs up`'s `phpFixedClockEnv` (framework `laravel`, `config.web.fixed_now` set) runs `php
  --ini` to find the project's own ini scan dir, composes `PHP_INI_SCAN_DIR=<existing scan
  dir>:<project>/.screens/web/php` (or just the second half when the existing dir is `(none)`,
  `composePhpIniScanDir`), and sets `SCREENS_FIXED_NOW` to the same instant as
  `capture.spec.ts`'s `FIXED_TIME`. Applied to both the `start_command` (serve) and the
  `seed_command` (migrate/seed) env, since the seed process is a separate `runner` call, not a
  child of `artisan serve`.
- Inert on a non-PHP framework or when `fixed_now` is unset in `config.json`: `phpFixedClockEnv`
  returns `{}` and no env var is set.
- Raw SQL `NOW()`/`CURRENT_DATE` is not covered by this (it runs inside the database, not PHP): the
  discoverer lists such views and the orchestrator adds a `mask[]` entry instead.
- **Faker's `dateTimeBetween`/`dateTimeInInterval`/`getMaxTimestamp` also read real wall-clock time**,
  independent of `Carbon::setTestNow()` (PHP's native `strtotime()`, not Carbon), so a demo
  seeder's `fake()->dateTimeBetween('-1 month', 'now')` reseeds with different dates on every run
  even with `fake()->seed()` pinned, breaking byte-hash determinism for anything the seed data
  feeds into. `screens/templates/php/FixedClockDateTime.php` is instantiated into
  `.screens/web/php/FixedClockDateTime.php`; `ScreensDemoSeeder` requires it and calls
  `fake()->addProvider(new FixedClockDateTime(fake()))` (and the same on any other bound
  `Faker\Generator` the project's factories use, e.g. a locale-specific one) before calling the
  project's own seeders. It extends `\Faker\Provider\DateTime` and overrides only
  `getMaxTimestamp`/`dateTimeBetween`/`dateTimeInInterval` (every other DateTime provider method
  delegates to these three through late static binding, verified against the installed
  `vendor/fakerphp/faker/src/Faker/Provider/DateTime.php`), resolving a relative/"now" string
  against `Carbon::now()->getTimestamp()` (so it agrees with `fixed-clock.php`) instead of real
  time; inert when `SCREENS_FIXED_NOW` is unset. Faker checks providers in reverse-registration
  order, so the last-registered provider's method shadows the built-in one without touching
  fakerphp/faker's vendor code.

## Seeder determinism rules (scaffold checklist, added after stage (b) STOP 3)

A demo seeder is deterministic only if every random draw is seeded. Five rules the Phase 2 scaffold
follows, and the demo seeder documents which ones actually applied:

1. **Faker seed on both generators.** `fake()->seed(<fixed>)` AND the same seed/provider setup on
   `app(\Faker\Generator::class)` (the locale-less singleton Eloquent's `Factory::withFaker()`
   resolves, distinct from `fake()`'s locale-keyed one — see above).
2. **Seeded string/UUID/ULID factories.** `Str::createRandomStringsUsing(...)` and
   `Str::createUuidsUsing(...)`/`Str::createUlidsUsing(...)` (or their `...UsingSequence()` helpers)
   with a fixed, deterministic sequence, set at the very start of the demo seeder — cheap and
   defensive even when no seeder in the chain currently calls `Str::random()`/`uuid()`/`ulid()`
   directly, since a later seeder addition would otherwise silently go non-deterministic.
3. **Laravel 13's secure Randomizer ignores every seed.** `Collection::random`/`Arr::random`,
   `->shuffle()`, `->inRandomOrder()` and `random_int()` all resolve through PHP's
   `Random\Randomizer` with the secure engine (`vendor/laravel/framework/src/Illuminate/Collections/Arr.php`
   `Arr::random`, verified: `(new Randomizer)->pickArrayKeys(...)`), which never reads
   `mt_srand`/`fake()->seed()`. The scaffold greps every seeder the demo seeder calls for
   `->random(`, `Arr::random`, `->shuffle(`, `inRandomOrder`, `random_int(` and, for each hit,
   either avoids calling that seeder or (when the seeder is otherwise needed, the common case)
   deletes the non-deterministic rows it created and recreates them deterministically inside the
   demo seeder itself (same factory, same count logic, a fixed selection — e.g. "first N rows
   ordered by id" — instead of the random pick).
4. **Row order without an `ORDER BY` tie-break can reorder between reseeds** even when every value
   in every row is identical. If a captured view differs only by row order, a `mask[]` is not the
   right tool (the content itself is correct, just reordered) — the manifest entry gets a
   `"known_nondeterministic": "<reason>"` field instead, and the Phase 8 report lists such entries
   separately; `screens.mjs`'s byte-identical verify count excludes them.
5. **`CACHE_STORE=array`** in the isolation env (`config.json`'s `web.env`, alongside
   `QUEUE_CONNECTION=sync`/`MAIL_MAILER=log`/`BROADCAST_DRIVER=log`) so a cached aggregate (e.g. a
   `Cache::remember(...)` badge count) never survives a reseed: `migrate:fresh` only resets database
   tables, not the project's configured cache store, so a `file`/`redis`-backed cache would keep
   serving a stale value from before the reseed.

## Preconditions

- `screens.mjs up --platform web` must have started the service and passed the DB guard;
  `BASE_URL` is `http://127.0.0.1:<config.web.port>` unless `SCREENS_BASE_URL` is set (override for
  a driver invoked outside the skill, e.g. manual debugging).
- Playwright must be a project devDependency (`npm i -D @playwright/test`, `npx playwright install
  chromium` once per machine; plan's "Per-project files" table, "Playwright devDependency where
  missing").

## Multi-step entries

A manifest entry with `steps[]` (Edge Cases: "view only reachable after a multi-step flow") is not
handled by this template; it navigates straight to `entry.reach` only. Multi-step replay is deferred
alongside the marketing renderer (stage c).
