# Web Driver (Playwright)

Invoked by `/screens` `SKILL.md` Phase 5's driver step (plan step 5) when `.screens/config.json` has
a `web` platform and `screens/templates/capture.spec.ts` has been scaffolded into
`<project>/.screens/web/capture.spec.ts` (Phase 2 scaffold, "Per-project files" table).

## Contents

- [Invocation](#invocation)
- [What the spec does](#what-the-spec-does)
- [Server-side fixed clock (PHP projects, added after stage (b) STOP 2)](#server-side-fixed-clock-php-projects-added-after-stage-b-stop-2)
- [Seeder determinism rules (scaffold checklist, added after stage (b) STOP 3)](#seeder-determinism-rules-scaffold-checklist-added-after-stage-b-stop-3)
- [Session cookie over http: SESSION_SECURE_COOKIE=false default](#session-cookie-over-http-session_secure_cookiefalse-default)
- [Server perf: parallel PHP workers, no per-request debug overhead, seed-on-change](#server-perf-parallel-php-workers-no-per-request-debug-overhead-seed-on-change)
- [Theme axis: cookie-driven dark mode, not prefers-color-scheme](#theme-axis-cookie-driven-dark-mode-not-prefers-color-scheme)
- [Error state: manifest-driven form submission](#error-state-manifest-driven-form-submission)
- [Preconditions](#preconditions)
- [Multi-step entries](#multi-step-entries)

## Invocation

From the target project root, after `screens.mjs up --platform web` reported `UP_RESULT=OK`:

```
cd <project root>
nice -n 10 npx playwright test .screens/web/capture.spec.ts --config .screens/web/playwright.config.ts --workers=<PLAYWRIGHT_WORKERS> [--grep <pattern>]
```

`<PLAYWRIGHT_WORKERS>` is `up`'s own `PLAYWRIGHT_WORKERS=<n>` output line (`min(4, floor(cores/2))`,
`screens.mjs`'s `playwrightWorkers`), never a hardcoded `--workers=4`: the user reported earlier runs
overloading the machine (plan's "Capture efficiency"), and `nice -n 10` applies to this process the
same way `screens.mjs up` already nices the PHP server and seed/migrate commands it starts.

`--config .screens/web/playwright.config.ts` (Phase 2 scaffold, next to `capture.spec.ts`) is always
explicit, never left to auto-discovery: it sets `outputDir: '../.run/playwright'` (Playwright
resolves `outputDir` relative to the config file's own directory, `.screens/web/`, not the project
root, so this lands at `<project root>/.screens/.run/playwright`) and `reporter: 'list'` so no
`test-results/`/`playwright-report/` ever land in the project root (both would otherwise appear even
on a passing run, since Playwright's default local reporter also writes an HTML report).

`--grep <pattern>` narrows the run to the entry ids `screens.mjs plan`'s `PLAN_ENTRY <id>
{new|stale|missing_png}` lines named (skip `unchanged` ids); omit the flag on a first run or
`--full` (every entry is already planned). Build the pattern as an alternation of entry ids with an
explicit start-of-string/whitespace boundary (test names are `${entry.id} ${state} ${role}`, see
below), e.g. `--grep "(?:^|\s)(dashboard|clients)\s"`. **Do not anchor with a bare `^`**: verified
against Playwright 1.63.0/zeit that `--grep "^dashboard"` matches zero tests even though the same
title without the anchor matches (the grep target is not simply the bare test title); `(?:^|\s)...`
is the verified working form and also avoids a substring false match like `admin-dashboard` against
a bare `dashboard`.

The spec reads `.screens/config.json` and `.screens/manifest.json` from `process.cwd()` at
test-collection time, not per-project templating, so the same `screens/templates/capture.spec.ts`
file works unmodified for every Laravel/web pilot (repo `CLAUDE.md` "Reviewer: every generated
driver must read the manifest at runtime instead of hard-coding entries").

## What the spec does

- One Playwright `test()` per entry x state x role (states/roles default to `['filled']`/`['guest']`
  when an entry omits them) -- **not** per viewport/theme too (revised 2026-09-24, "Capture
  efficiency"): one context, one login, one navigation per test.
- `page.clock.setFixedTime('2026-05-12T09:41:00+02:00')` before navigation (topf-secret's
  `-ScreensFixedDate` convention, web equivalent).
- A CSS override disables all animations/transitions (`animation-duration`/`transition-duration:
  0s !important`).
- `context.route('**/*', ...)` allows only `localhost`/`127.0.0.1` requests, aborts everything else
  (no live third-party calls from a demo run; plan's "Dynamic content" edge case).
- Login: `role: "guest"` skips login; any other role posts `config.demo_logins[role]` /
  `.screens/secrets.local.json`'s `demo_password` (no demo password in any repo, see
  `config-schema.md` "Demo password") through `/login` (`input[name=email]`, `input[name=password]`,
  `button[type=submit]`), then `waitForLoadState('networkidle')`.
- Navigation: `page.goto(BASE_URL + entry.reach)`, `waitForLoadState('networkidle')`, then
  `entry.ready` (a CSS selector) via `waitForSelector` and/or `entry.ready_text` (a visible-text
  match via `getByText(..., { exact: false })`) if set -- both wait when both are set; `entry.mask`
  selectors and the `error` state's form submission are applied once, right after this single
  navigation.
- **Device-class x theme loop, in the same page (Capture efficiency):** for each `viewport` in
  `config.axes.viewports.web`, `page.setViewportSize` + two `requestAnimationFrame` ticks +
  `waitForLoadState('networkidle')` (an entry with `reload_per_viewport: true` gets a fresh
  `page.goto` + mask/error re-application instead); for each `theme` inside that viewport,
  `page.emulateMedia({colorScheme})` + `context.addCookies([{name:'dark_mode',...}])` (for any later
  navigation) + `document.documentElement.classList.toggle('dark', ...)` via `page.evaluate` (drives
  the project's own client-side class the way a live toggle would, since a cookie alone only takes
  effect on the next full navigation) + two rAF ticks, then the screenshot. No reload between
  device-class/theme combinations unless the entry opts in.
- Output: `.screens/.incoming/web/<entryId>__<state>__<role>__<viewport>__<theme>.png`, `fullPage:
  true`, matching the filename shape `screens.mjs promote` parses (`<entryId>__<rest>.png`);
  `promote` maps `<viewport>` to a device class (`config.axes.device_classes.web`) and drops it from
  the final filename (Output layout, `references/config-schema.md`).

### `reload_per_viewport` (manifest flag)

Set on a manifest entry only when a same-page viewport switch genuinely differs from a fresh reload
at that viewport (verified once per candidate entry with an ImageMagick `compare -metric AE` between
the two capture paths, not assumed) -- e.g. a view whose mobile layout is server-rendered
differently rather than purely CSS-responsive. Every other entry stays on the one-navigation path.

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
   resolves, distinct from `fake()`'s locale-keyed one, see above).
2. **Seeded string/UUID/ULID factories.** `Str::createRandomStringsUsing(...)` and
   `Str::createUuidsUsing(...)`/`Str::createUlidsUsing(...)` (or their `...UsingSequence()` helpers)
   with a fixed, deterministic sequence, set at the very start of the demo seeder (cheap and
   defensive even when no seeder in the chain currently calls `Str::random()`/`uuid()`/`ulid()`
   directly, since a later seeder addition would otherwise silently go non-deterministic).
3. **Laravel 13's secure Randomizer ignores every seed.** `Collection::random`/`Arr::random`,
   `->shuffle()`, `->inRandomOrder()` and `random_int()` all resolve through PHP's
   `Random\Randomizer` with the secure engine (`vendor/laravel/framework/src/Illuminate/Collections/Arr.php`
   `Arr::random`, verified: `(new Randomizer)->pickArrayKeys(...)`), which never reads
   `mt_srand`/`fake()->seed()`. The scaffold greps every seeder the demo seeder calls for
   `->random(`, `Arr::random`, `->shuffle(`, `inRandomOrder`, `random_int(` and, for each hit,
   either avoids calling that seeder or (when the seeder is otherwise needed, the common case)
   deletes the non-deterministic rows it created and recreates them deterministically inside the
   demo seeder itself (same factory, same count logic, a fixed selection: "first N rows
   ordered by id" instead of the random pick).
4. **Row order without an `ORDER BY` tie-break can reorder between reseeds** even when every value
   in every row is identical. If a captured view differs only by row order, a `mask[]` is not the
   right tool (the content itself is correct, just reordered): the manifest entry gets a
   `"known_nondeterministic": "<reason>"` field instead, and the Phase 8 report lists such entries
   separately; `screens.mjs`'s byte-identical verify count excludes them.
5. **`CACHE_STORE=array`** in the isolation env (`config.json`'s `web.env`, alongside
   `QUEUE_CONNECTION=sync`/`MAIL_MAILER=log`/`BROADCAST_DRIVER=log`) so a cached aggregate (e.g. a
   `Cache::remember(...)` badge count) never survives a reseed: `migrate:fresh` only resets database
   tables, not the project's configured cache store, so a `file`/`redis`-backed cache would keep
   serving a stale value from before the reseed.

No demo password in any repo (`config-schema.md` "Demo password"): the demo seeder reads
`DEMO_USER_PASSWORD` from the environment (`screens.mjs up` sets it, from
`.screens/secrets.local.json`, on both the seed and serve command) and throws (`RuntimeException` or
the framework's equivalent) when it is empty -- never a hardcoded fallback password.
`secret_env_aliases` (`config-schema.md`) additionally sets any listed alias name to the same value,
for a project whose own env var for the demo password is not called `DEMO_USER_PASSWORD`.

## Session cookie over http: SESSION_SECURE_COOKIE=false and SESSION_EXPIRE_ON_CLOSE=true defaults

`screens.mjs up` sets two session-cookie env vars on every `laravel` project's isolation env
(`laravelSessionEnv`), merged in *before* `config.web.env` so a project's own values in `config.json`
still win:

- **`SESSION_SECURE_COOKIE=false`.** Live STOP (2026-09-24, events pilot): a Laravel project's
  default `config/session.php` sets `'secure' => env('SESSION_SECURE_COOKIE', true)`, so a browser
  drops the session cookie after login against the isolated backend, which serves over plain http.
- **`SESSION_EXPIRE_ON_CLOSE=true`.** Live STOP (2026-09-24, events pilot, found the same day as the
  fix above): the server-side fixed clock (`fixed-clock.php`'s `Carbon::setTestNow($fixedNow)`)
  freezes every `now()` the running `php artisan serve` process computes, including the session
  cookie's `Expires`/`Max-Age`, which Laravel derives as `now()->addMinutes($lifetime)`. Once real
  wall-clock time passes `config.web.fixed_now`, that computed expiry is already in the past -- the
  browser discards the `Set-Cookie` header on arrival, so every login silently fails to persist past
  the very next request (reproduced against events: `fixed_now` 2026-05-12, real date 2026-09-24,
  every `Set-Cookie: <session>=...; expires=Tue, 12 May 2026 ...` immediately expired; only the
  guest-role entries, which never log in, captured correctly). `session.expire_on_close` makes
  Laravel omit `Expires`/`Max-Age` entirely (a browser-session cookie instead), so the frozen clock
  can no longer produce an already-expired header; server-side session-lifetime enforcement still
  reads the same frozen `now()`, so it stays internally consistent with the rest of the isolated run.
  Checked whether the zeit pilot's own `config/session.php` explains why it never hit this: it does
  not -- zeit's `expire_on_close` also defaults to `env('SESSION_EXPIRE_ON_CLOSE', false)` and its
  `.screens/config.json` carries the same `fixed_now` (2026-05-12). zeit not hitting this bug is more
  likely explained by its own last authenticated `/screens` run having happened before real time
  passed that date, not by a differing session config.

## Server perf: parallel PHP workers, no per-request debug overhead, seed-on-change

Added 2026-09-24 after the user reported earlier runs overloading the machine (plan's "Capture
efficiency"):

- `screens.mjs up` sets `PHP_CLI_SERVER_WORKERS=4` and `APP_DEBUG=false` on a `laravel` project
  before starting `artisan serve`, so the built-in dev server handles the Playwright workers'
  parallel requests instead of serializing them, and drops the debugbar/error-page overhead per
  request (`laravelPerfEnv`).
- `up` runs `php artisan view:cache` once before starting the server (never `config:cache`, see the
  Laravel DB guard) to precompile Blade views.
- Every process `up` starts (the server, `view:cache`, the seed/migrate command) runs under
  `nice -n 10`; the driver invocation (above) is niced by the caller for the same reason.
- **Seed-on-change:** `up` fingerprints `database/migrations/**`, `database/seeders/**`,
  `database/factories/**`, the instantiated `.screens/web/php/*` files, and `fixed_now`
  (`computeSeedFingerprint`). When that fingerprint matches the value stored from the last run AND
  the isolated DB already exists (implied by the Laravel DB guard passing), `up` reports
  `SEED=SKIP (unchanged)` instead of running `migrate:fresh --seed`. `--full`/`--reseed` force a
  reseed regardless.
- `up`'s output includes `PLAYWRIGHT_WORKERS=<min(4, floor(cores/2))>`, read by the driver
  invocation above instead of a hardcoded worker count.

## Theme axis: cookie-driven dark mode, not prefers-color-scheme

Some projects switch themes with a server-read cookie/session value instead of the OS-level
`prefers-color-scheme` media query (e.g. `apps/zeit/app`: every layout resolves
`session('dark_mode', request()->cookie('dark_mode') === 'true')` server-side to decide the `dark`
class on `<html>`). Playwright's `colorScheme` context option alone does not reach that. The
scaffold checks for this (grep the project's layouts for a dark-mode cookie/session/localStorage
read) and `capture.spec.ts` sets both: `colorScheme: 'dark'|'light'` (for any OS-level media-query
fallback elsewhere) AND `context.addCookies([{ name: 'dark_mode', value: 'true'|'false', ... }])`
before navigation, for a theme value of `dark`/`light`.

## Error state: manifest-driven form submission

An entry whose `states` includes `error` needs `error_fill` (`{selector, value}` pairs) in the
manifest; `capture.spec.ts` fills those fields on the already-loaded `entry.reach` page and submits
by pressing Enter in the LAST listed field, so the screenshot shows the project's own real
server-side validation error, not a synthetic one. Only entries that are genuinely forms (auth
pages, not every list/dashboard view) get this state.

**Submit via Enter, not a button click** (verified against `apps/zeit/app`, both `loginAs` and
`submitErrorState` use this): clicking the scoped `button[type=submit]` intermittently produced
zero network requests at all (no Livewire update call, confirmed by listening to every `response`
event) on this project's `<x-button>` component, while pressing Enter in the form's last field
reliably fires the same `wire:submit.prevent` handler every time. `submitScopedForm(page,
lastFieldSelector)` defaults to `input[name=password]` (the login form) and `submitErrorState`
passes the last `error_fill` selector, so a multi-field form (e.g. a register form's
`password_confirmation`) submits from the field a real user would be on when pressing Enter. A
300ms settle wait after `networkidle` covers the client-side DOM morph that renders the validation
error, which lands a tick after the response itself.

**Not every form reliably validates on Enter either**: a register-style form with more than two
fields (name, email, password, password_confirmation) did not trigger its Livewire validation via
Enter in this project even from the last field, cause not fully isolated within this stage's
budget. Rather than ship an unverified capture, that entry's `error` state was dropped (kept
`filled` only) and the gap is recorded here: verify a candidate `error` entry's capture manually
(inspect the PNG for real red/error text, not just "the run passed") before trusting it, and prefer
two-field forms (login-style) for this state until the multi-field case is diagnosed.

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
