# /screens: Screenshot Catalog of Every View in Every State

> **Executor instruction:** Follow step by step, check each verify
> criterion before moving on. If a STOP condition occurs: stop and
> report, do not improvise.
>
> **Drift check (first):** `git diff --stat 3f7a134..HEAD -- audit/bin/detect-framework.sh audit/bin/capture-screens.sh design-audit/references/surface-taxonomy.md agents/ README.md CLAUDE.md`
> If an in-scope file has changed since the plan was created: reconcile the
> current state against the live code; on a mismatch, that is a STOP condition.

## Meta
- Planned at: commit `3f7a134`, 2026-09-24
- Status: Implemented on branch `worktree-agent-a632240e63fef4b86` (not yet merged to main)
- Repo: `/Users/rafael/Developer/claude/skills` (skill source repo; the Stop hook `~/.claude/hooks/sync-skills.sh` symlinks every folder with a `SKILL.md` into `~/.claude/skills/`, no registration file needed)

## Problem
There is no way to get a complete, current picture of what a project looks like. Screens exist only as ad-hoc captures (`/delegate` before/after, `apps/events/tests/Browser/screenshots`, `apps/topf-secret/ios/RezepteAppUITests/ScreenshotTourTests.swift`), with whatever data happens to be around, and they go stale silently. Design reviews and store/marketing work start from zero every time.

## Goal
One command, `/screens`, run inside any project:
1. First run: creates a per-project config and view manifest (JSON under `.screens/`), asks the user once to confirm, generates a demo seeder and capture drivers, then captures every view in every applicable state.
2. Later runs: no questions (except when the committed start/seed commands changed, see Trust boundary); capture only views that are new or whose source changed; unchanged PNGs stay byte-identical.
3. Output lands in sorted folders inside the repo (gitignored), with a filterable `index.html`, plus App-Store-ready marketing renders with device frame and headline.

Measurable: on the web pilot (`apps/zeit/app`), a second run with no source changes captures 0 screens and finishes under 60 s after services are up; editing one Blade view recaptures only that view's entries.

## Non-Goals
- Visual regression gating in CI (no CI workflows, per global rule).
- Physical devices (`devicectl` has no screenshot subcommand, see `audit/bin/capture-screens.sh:8-9`).
- Live agent-driven clicking on every run (discovery is agent work, capture is scripted).
- Removing `/delegate`'s existing capture path (`audit/bin/capture-screens.sh` stays as the fallback; step 11 adds `/screens` in front of it).
- CLI or WordPress-Local projects (`detect-framework.sh` generic → skill reports SKIP).
- Pixel-threshold diffing (see Approach; revisit only with pilot evidence).

## Out of Scope (Files)
- `audit/bin/capture-screens.sh`: used by `/delegate` Phase 3.5/5 with a fixed contract and stays the fallback for repos without `.screens/`; `/screens` gets its own tooling instead of widening that contract.
- `design-audit/**`: read the surface taxonomy, do not edit it.
- Any project `.env*` file: never read or written (global rule). Isolation goes through process env overrides only.
- Existing UI tests in pilots (`apps/topf-secret/ios/RezepteAppUITests/*`): read as exemplar, do not modify; `/screens` adds its own test class.

## Solution

### Approach
**Agent discovers, scripts capture.** Claude does the expensive thinking once (which views exist, which states matter, how to reach them, what demo data makes them look real) and writes it down as a committed manifest plus deterministic driver code in the project. Every run after that is a script execution; Claude only re-enters for discovery deltas (new routes/views since the last run) and for failures.

Prior art borrowed (research 2026-09-24, no existing tool covers the full chain seed → states → multi-platform → incremental):
- Manifest schema after BackstopJS scenarios (view × state × viewport, selectors to hide/mask) and shot-scraper's declarative URL list.
- Web capture with Playwright: `page.clock.setFixedTime`, `animations: 'disabled'`, `mask`, `colorScheme` emulation.
- Apple capture with XCUITest after the user's own pattern in `apps/topf-secret/ios/RezepteAppUITests/UITestLauncher.swift` (master launch argument → in-memory store, named seed scenarios) and `ScreenshotTourTests.swift` (PNG written to a host dir from `TEST_RUNNER_SCREENSHOT_DIR`, light/dark variant). Named checkpoints across a device × locale matrix after fastlane snapshot.
- Android and Capacitor (webview) capture via Maestro flows (`takeScreenshot`, works on webviews).
- Status bar: `xcrun simctl status_bar <udid> override --time 9:41 --batteryLevel 100 --cellularBars 4`, Android System UI demo mode via `adb shell`.
- Change detection: own per-view source fingerprint (no canonical OSS tool exists) plus sha256 of the PNG bytes. No pixel decoder: with fixed clock, disabled animations, masks and fixed demo data, identical pixels produce identical PNG bytes from the same encoder, so a byte hash is enough. (Simplicity challenge; also removes the unsupported-PNG-profile failure class the architecture challenge raised.)

**Driver choice** (user decision, revised after finding the topf-secret pattern): XCUITest for native iOS and macOS, Maestro for Android and for Capacitor apps on both mobile OSes (XCUITest drives webviews poorly).

### Data flow

```
/screens [platform] [--full]
  ├─ .screens/config.json missing? ──► DISCOVERY (first run)
  │     detect-framework.sh ─► screens-view-discoverer agent (per platform)
  │     ─► orchestrator writes config.json + manifest.json drafts
  │     ─► user confirms (summary incl. marketing hero list + commands to be run)
  │     ─► executor subagent writes demo seeder + drivers ─► seeder dry run on isolated DB
  ├─ trust check           command fields of config.json hash == last confirmed hash? else re-confirm
  ├─ screens.mjs plan      manifest + fingerprints vs state.json ─► work list (new/stale/removed)
  │     route/view files changed since state.commit? ─► discoverer in delta mode ─► manifest patch
  ├─ per platform (web, ios, android, macos last):
  │     screens.mjs up       isolated DB guard, seed, start services, dedicated device, health
  │     driver               playwright --grep / xcodebuild -only-testing / maestro test <flows>
  │                          raw PNGs into .screens/.incoming/<platform>/
  │     screens.mjs promote  byte-hash compare, write changed, move removed to _removed/, update state.json
  │     screens.mjs down     always (trap)
  ├─ screens.mjs marketing   render framed store images for marketing entries whose source PNG or headline changed
  └─ screens.mjs index       regenerate screenshots/index.html
```

Promote runs per platform so an interrupted run keeps every platform already finished (architecture challenge).

### Per-project files (all created by the skill, in the target repo)

| Path | Committed | Content |
|---|---|---|
| `.screens/config.json` | yes | platforms, start/stop commands, env overrides for DB isolation, expected isolated DB path, health checks, ports, seeder command, roles + demo logins, axes (viewports/devices, themes, locales), `global_sources`, `route_sources`, marketing settings |
| `.screens/manifest.json` | yes | one entry per view: `id`, `platform`, `area`, `view`, how to reach it (url / XCUITest navigation / Maestro steps), `states[]` (each with setup: demo account, query, route mock, form input), applicable `roles`, `sources[]` globs, `mask[]` selectors, `ready` selector |
| `.screens/web/capture.spec.ts` | yes | Playwright spec reading the manifest at runtime, one test per entry × state × role × viewport × theme, filtered with `--grep` |
| `.screens/maestro/*.yaml` | yes | Android / Capacitor flows, one per manifest entry |
| `<App>UITests/ScreensCatalogTests.swift` (+ target in `project.yml` if the app has no UI test target) | yes | iOS/macOS, one test method per entry, reads manifest ids from env |
| Demo seeder (`database/seeders/ScreensDemoSeeder.php`, `scripts/seed-screens.ts`, Swift `ScreensDemoData.swift` behind a launch argument, `#if DEBUG`; reuse an existing launch-arg vocabulary such as `-UITests -UITestSeed <scenario>` when the app has one) | yes | realistic demo data in the project's locales, fixed faker seed, fixed demo accounts per role plus one `empty` account per role for empty states |
| `.screens/state.json` | no (gitignored) | last-run commit, confirmed command hash, per-entry fingerprint + PNG sha256 |
| `screenshots/` | no (gitignored) | output |

Output layout (revised 2026-09-24, user request: split by capture device): `screenshots/<platform>/<device-class>/<area>/<view>/<state>__<role>__<theme>[__<locale>].png`, device-class from config (`desktop`, `mobile`, `tablet` for web viewports; `iphone`, `ipad`, `android-phone`, `mac` for apps; each class maps to exactly one size in config, a second size of the same class gets a suffixed class like `desktop-wide`) (locale suffix only when more than one locale is configured), marketing under `screenshots/_marketing/<platform>/<locale>/<store-format>/<NN>-<id>.png`, removed views under `screenshots/_removed/<date>/...`.

### State axes (user decision: all four, plus locale for marketing)
- Data: `empty` (per-role empty demo account), `filled` (default demo account), `error` (validation: submit invalid form input; server error: Playwright `page.route` returning 500; native via a `-ScreensError <id>` launch arg only where the discoverer finds an error view).
- Viewports/devices: web `1440x900` and `390x844`; iOS iPhone 17 Pro + iPad Pro 13"; Android Pixel 9 (emulator `-no-window`); macOS one window size from config.
- Theme: light + dark only when the project supports dark mode (discoverer checks `dark:` Tailwind variants, `prefers-color-scheme`, `.preferredColorScheme`, asset catalog appearances); otherwise light only.
- Roles: guest / each seeded role, per entry only the roles that can reach it.
- Locale (product challenge): default = the project's primary locale (`config/app.php` `locale`, `developmentRegion` / `.lproj` default, `values/` default); fallback German. Catalog captures use the primary locale only; marketing entries are captured in every locale listed in `marketing.locales` (e.g. `apps/events/native/store-assets/` has `ios-de`, `ios-en`, `android-de`, `android-en`).

The manifest lists per entry which axes apply, so the product never multiplies blindly. The first-run summary shows the planned total.

### Incremental rule (user decision: new + changed)
Fingerprint per entry = sha256 over the contents of its `sources[]` globs plus `global_sources` from config. `global_sources` default: CSS/token files, layout files, the demo seeder, the platform's driver file, and the dependency lockfiles (`composer.lock`, `package-lock.json`/`bun.lock`, `Package.resolved`, `gradle/libs.versions.toml`) so a framework or CSS-library bump invalidates everything (risk challenge: fingerprint false negatives). An entry is recaptured when it is new, its fingerprint changed, or its PNG is missing. `--full` recaptures everything regardless of fingerprints; the report suggests it when the last full run is older than 30 days. `promote` compares the new PNG's sha256 with the stored one and leaves the old file untouched when equal. When the hashes differ and ImageMagick `compare` is on PATH, it runs `compare -metric AE -fuzz 2%` and keeps the old file when the differing pixel count is at most `diff_tolerance` (default 0.01 % of the image area); without ImageMagick it stays byte-exact and the report says so (revised 2026-09-24: headless Chromium font anti-aliasing jitters 1-100 px across runs even with `--disable-gpu`). Entries no longer in the manifest move to `_removed/<date>/`.

Discovery delta: when files matching `route_sources` (e.g. `routes/*.php`, `src/pages/**`, SwiftUI `*View.swift`) changed since `state.commit`, the discoverer runs in delta mode on `git diff --name-only <state.commit>..HEAD -- <route_sources>` and proposes manifest additions/removals. Additions are applied without asking (triage) and reported; hand-edited entries are never overwritten.

### Marketing (user decision: framed renders in v1)
- Config `marketing.entries` (discoverer proposes 5-8 hero screens per platform), `marketing.headlines` (per entry per locale, written by Claude on first run), `marketing.locales`, `marketing.formats` (iOS 6.9" 1320x2868, iPad 13" 2064x2752, Android phone 1080x1920, macOS 2880x1800, web 1920x1080).
- Review gate (product + design challenge, convergent): every headline carries `"reviewed": false` until the user sets it to true (or confirms in the first-run summary). Renders with unreviewed headlines land in `_marketing/_draft/` instead of `_marketing/`, and the report lists them as `NEEDS REVIEW`. `index.html` has a marketing section showing each render next to its headline text and config path, so review needs no JSON-to-PNG cross-referencing.
- Rendering: an HTML template in the skill (`screens/templates/marketing.html`) with a CSS-drawn device bezel (no third-party frame assets), headline, background from the project's token source (the token file named in the project's `DESIGN.md`; fallback neutral). Rendered with Playwright at exact store pixel size. Only re-rendered when its source PNG hash or its headline/config changed.

### index.html (design challenge)
Single static file, embedded JSON + vanilla JS, no server, no dependencies. Grouped platform → area → view; filter toggles for every axis (state, role, device/viewport, theme, locale); per view a strip of its states; click opens the full-size PNG. Top: run summary (new/updated/unchanged/removed/failed, date, commit). Marketing section as described above.

### Isolation and lifecycle
- **Laravel DB guard (risk challenge, Critical).** Laravel's env repository is immutable (`vendor/laravel/framework/src/Illuminate/Support/Env.php:89`, verified in `apps/zeit/app`), so process env wins over `.env`. Two ways it can still hit the real DB, both guarded in `screens.mjs up` before any migrate/seed command runs:
  1. A config cache (`bootstrap/cache/config.php`) ignores env entirely → hard FAIL with "run php artisan config:clear".
  2. Any other misresolution → `screens.mjs up` runs `php artisan db:show --json` with the override env and reads `platform.config.driver` / `platform.config.database` (real shape verified in `apps/zeit/app`). Isolation uses the project's own driver (revised 2026-09-24 after the zeit pilot STOP: zeit and events are Postgres-only by design, 19 zeit migrations use pgsql-only constructs):
     - `sqlite` projects (e.g. `apps/finances`): `DB_DATABASE=<repo>/.screens/screens.sqlite`; guard passes only when the resolved driver is `sqlite` and the path equals `isolated_db`.
     - `pgsql` projects (e.g. `apps/zeit/app`, `apps/events`): only `DB_DATABASE=<isolated_db>` is overridden, host/user/password stay as the project resolves them. Guard passes only when the resolved driver is `pgsql`, the resolved database equals `isolated_db`, `isolated_db` ends in `_screens`, AND it differs from the database resolved WITHOUT the override (second `db:show --json` call, no env) so a config that points dev at a `_screens` name still fails. Missing database: `createdb <isolated_db>` (plain local socket, Homebrew Postgres); on failure FAIL with the command to run.
     - `mysql`/other drivers: FAIL (unsupported in v1) with the driver name.
     Only after the guard passes, `migrate:fresh --seed --seeder=ScreensDemoSeeder --force` runs, with the same env. `down` never drops the pgsql database (reused next run, `migrate:fresh` resets it); it deletes only the sqlite file.
  Queue/mail/broadcast set to `sync`/`log`/`log` via env.
- **Server-side fixed clock (revised 2026-09-24 after stage (b) STOP 2: dashboard aggregates used real `now()`, the Playwright clock only fakes the browser).** PHP projects: `.screens/web/php/zz-screens.ini` with `auto_prepend_file=<repo>/.screens/web/fixed-clock.php`, activated via env `PHP_INI_SCAN_DIR=<php --ini scan dir>:<repo>/.screens/web/php` on the serve AND the seed/migrate commands (child processes of `artisan serve` inherit env). `fixed-clock.php` requires `vendor/autoload.php` and calls `Carbon\Carbon::setTestNow(getenv('SCREENS_FIXED_NOW'))` (Carbon 3 shares test-now with CarbonImmutable) only when `SCREENS_FIXED_NOW` is set, so the file is inert otherwise. No project source file changes. Bun/Node backends: the discoverer names the project's clock seam; without one, `now`-dependent entries get `mask[]`. Raw SQL `NOW()`/`CURRENT_DATE` is not covered: the discoverer lists such views and they get masks.
- **Seeder determinism rules (revised 2026-09-24 after stage (b) STOP 3).** The demo seeder is deterministic only if every random draw is seeded. Rules for the scaffold, documented in `platform-web.md`: (1) `fake()->seed(<fixed>)` AND the same provider/seed on the locale-less `app(\Faker\Generator::class)` Eloquent factories use (they differ from `fake()`); (2) `Str::createRandomStringsUsing` and `Str::createUuidsUsing`/`createUlidsUsing` with a seeded sequence at seeder start; (3) Laravel 13 `Arr::random`/`Collection::random`/`shuffle` use `Random\Randomizer` with the secure engine and ignore every seed: the scaffold greps every seeder the demo seeder calls for `->random(`, `Arr::random`, `->shuffle(`, `inRandomOrder`, `random_int`, and either avoids calling that seeder or post-processes its output deterministically inside the demo seeder; (4) lists without `ORDER BY` a tie-break can reorder: if a view differs only by row order, mask is not allowed, the manifest entry gets a `known_nondeterministic` note and the report lists it; (5) `CACHE_STORE=array` in the isolation env so cached aggregates never survive a reseed.
- Bun/Hono: the discoverer finds the DB path env var (e.g. `DATABASE_PATH`); `up` verifies the resolved path is inside `.screens/` before seeding.
- Astro/static: `astro dev --port <port>`, no seeding.
- iOS/macOS native: launched with the app's demo launch argument plus `-ScreensFixedDate 2026-05-12T09:41:00Z`; the app swaps its store for an in-memory store filled from `ScreensDemoData` (or the existing seed scenarios). Apps with a local backend (config `depends_on`) get the backend started in isolation first.
- Capacitor (`apps/events/native`): backend isolated as web, app built via `npx cap sync` + `xcodebuild -sdk iphonesimulator` / `./gradlew assembleDebug`, driven by Maestro.
- **Dedicated devices (architecture challenge).** `up` creates, once, a simulator named `screens-<repo-hash>-<device>` via `xcrun simctl create` and an AVD `screens_<repo-hash>_<device>`, reused across runs, never the user's currently booted device. Booted headless (`simctl boot` without Device Hub, emulator `-no-window -no-audio`), shut down in `down`.
- Ports: checked free before start; next free port for this run, recorded in the run, not in config.
- `down` kills the process group via PID file and deletes temp DBs; the skill wraps each platform in a trap so `down` always runs.
- Lock file `.screens/.lock` prevents two runs in one repo.
- **Capture efficiency (revised 2026-09-24, user: run too slow, machine overloaded).** One navigation per (entry, state, role); all device-class × theme shots taken in that page by switching theme (emulateMedia + project dark toggle) and viewport (setViewportSize + layout settle) without reload; `reload_per_viewport: true` per entry only where a fresh load differs (checked by ImageMagick compare on sample entries). Login once per role via storageState. PHP: `PHP_CLI_SERVER_WORKERS=4`, `APP_DEBUG=false`, `view:cache` (never `config:cache`); Playwright workers = min(4, cores/2). Driver and server run under `nice -n 10`. `up` skips `migrate:fresh`+seed when the fingerprint of migrations/seeders/factories/seeder templates/`fixed_now` is unchanged and the isolated DB exists (`--full`/`--reseed` force it).
- macOS XCUITest runs visibly and takes focus: announced before, run last.
- **Disk guard (revised 2026-09-24, 19 GB free at the time).** Apple and Android builds use a per-run `-derivedDataPath .screens/.build/<platform>` (gitignored, deleted in `down`); `up` checks free space on the volume and reports `SKIP (low disk: <N> GB free, need 8)` below 8 GB. Config `devices` may list fewer devices than the defaults (pilot: iPhone only).

### Trust boundary (risk challenge)
`.screens/config.json` is a fourth repo-supplied command site next to `test-command:`, `deploy-command:` and `perf-measure:` (repo `CLAUDE.md` Gotcha "Three sites run a repo-supplied command string"). Treatment: `state.json` stores the sha256 of all command fields confirmed by the user. When the current hash differs (config edited, repo cloned fresh), the skill shows the commands and asks once before running them. Rationale: `migrate:fresh` is destructive, unlike a test command. Add this site to that Gotcha in step 10.

### Invocation
`/screens` (all configured platforms, incremental), `/screens <platform>` (one platform, product challenge; does not touch config), `/screens --full` (ignore fingerprints). German triggers in `when_to_use`.

### Steps
1. **Skeleton.** `screens/SKILL.md` (frontmatter like `design-audit/SKILL.md:1-18`: `name`, `description` with "NOT for before/after capture of one change (that is /delegate)", `when_to_use` with German triggers "alle Screens aufnehmen, Screenshots aktualisieren, Screens-Katalog, App-Store-Screenshots", `argument-hint: "[web|ios|android|macos] [--full]"`, `model: inherit`, `effort: medium`, `allowed-tools`), plus `screens/references/config-schema.md` (JSON schema for config + manifest, one Laravel and one iOS example, TOC if >100 lines). → verify: files exist; `wc -l screens/SKILL.md` < 500.
2. **Core CLI** `screens/bin/screens.mjs` (Node ≥20, built-ins only, like `audit/bin/compute-floor.mjs`), subcommands `plan`, `up`, `down`, `promote`, `marketing`, `index`, `trust`, `affected --files <list>` (entry ids whose `sources`/`global_sources` match the given paths, for /delegate, see step 11); each emits `KEY=value` lines and a final `SCREENS_RESULT=OK|SKIP (reason)|FAIL (reason)` (contract style of `audit/bin/capture-screens.sh:20-23`). Tests `screens/bin/screens.test.mjs` (`node --test`), one per branch: new entry → planned; unchanged → skipped; source change → stale; global invalidator (lockfile) change → all stale; missing PNG → planned; `--full` → all planned; removed entry → moved to `_removed`; promote equal hash → old file untouched (mtime unchanged); promote different hash → replaced; lock present → FAIL; Laravel guard: config cache present → FAIL; guard: resolved DB path ≠ isolated path → FAIL (stub `db:show` output); pgsql guard: isolated name equals dev DB → FAIL, name without `_screens` → FAIL, matching `_screens` DB distinct from dev → OK; unsupported driver → FAIL; trust: changed command hash → `NEEDS_CONFIRM`; marketing: unreviewed headline → output under `_draft`; affected: a path in one entry's `sources` → only that id, a `global_sources` path → all ids, an unrelated path → none. → verify: `node --test screens/bin/` exit 0, ≥ 17 tests, each red when its branch is inverted.
3. **Discoverer agent.** Worker spec `screens/agents/view-discoverer.md` (no frontmatter, `# Subagent N: Name` + bullet list, repo convention) and registered definition `agents/screens-view-discoverer.md` (YAML frontmatter, points at the worker spec, pattern `agents/design-surface-mapper.md`), model sonnet, tools Read, Grep, Glob, Bash (read-only commands like `php artisan route:list --json`). Reads routes, nav, controllers/views (web) or SwiftUI view tree / tab + navigation destinations (apps), existing UI-test launch vocabularies and existing screenshot tooling (project `CLAUDE.md` mentions, e.g. `apps/events` `composer test:screenshots`, `apps/casa` `SeededSweepUITests` + `bun run seed-demo-family`, `apps/topf-secret` `ScreenshotTourTests`; reuse their seed scenarios instead of inventing parallel ones), seeders, auth/roles, dark-mode support, primary locale. Checks against `design-audit/references/surface-taxonomy.md` for expected surfaces it might have missed. Returns structured output (manifest entries, config draft, demo-data brief, marketing hero proposals); the orchestrator writes the files. → verify: dry run against `apps/zeit/app` returns a manifest whose route count equals `php artisan route:list --method=GET --json | jq length` minus API/asset routes, each exclusion listed with reason.
4. **SKILL.md orchestration.** Phases: 0 preflight (detect-framework, lock, args), 1 discovery (first run only; one AskUserQuestion showing counts per platform, axes, planned total, the marketing hero list with headlines, and the exact start/seed commands), 2 scaffold (sonnet executor writes seeder + drivers from the brief, then seeder dry run via `screens.mjs up`), 3 trust check, 4 plan + delta discovery, 5 per-platform loop (up → driver → promote → down), 6 marketing, 7 index, 8 report (table platform × new/updated/unchanged/removed/failed, `NEEDS REVIEW` list, path to `screenshots/index.html`). Single-entry failures do not abort; each listed with the driver's error line. Bash blocks follow the fresh-shell rule (repo `CLAUDE.md` Gotchas). Run ledger: `orch_run_log --start --skill screens` in Phase 0 and `orch_run_log --skill screens --outcome <ok|partial|fail> --counts "new=..,updated=..,failed=.."` in Phase 8, like `/plan-it` (evaluation: monitoring blind spot). → verify: `bash audit/bin/check-fresh-shell.sh .` reports no hit in `screens/`.
5. **Web driver** `screens/references/platform-web.md` + `screens/templates/capture.spec.ts` (manifest read at runtime; storageState login per role; `page.clock.setFixedTime('2026-05-12T09:41:00+02:00')`; `animations: 'disabled'`; mask; external hosts blocked via `page.route` allowlist localhost; `waitForLoadState('networkidle')` + entry `ready` selector; output `.screens/.incoming/web/`; `--workers=4`). Pilot `apps/zeit/app` (Laravel 13, own port, not 8001). → verify: first run PNG count == `plan`'s planned count; 5 random PNGs show demo data, no debugbar; `database/screens.sqlite` exists and the dev DB is unchanged (row count of one table before/after).
6. **Incremental verification on zeit.** Run 2a without changes (plan must report 0 to capture); run 2b `--full` without changes (determinism); run 3 after adding a harmless class to one Blade view listed in exactly one entry's `sources`. → verify: run 2a planned=0; run 2b `new=0 updated=0`, all PNG sha256 unchanged; run 3 recaptures only that entry.
7. **Marketing + index.** `screens/templates/marketing.html`, `screens/templates/index.html`, `screens.mjs marketing|index`. → verify: in zeit, `_marketing/_draft/de/1920x1080/*.png` at exactly 1920x1080 (`sips -g pixelWidth -g pixelHeight`); after setting `reviewed: true` on one headline, that render moves to `_marketing/de/1920x1080/`; `index.html` opens from disk, filters toggle (browser proof screenshot); filters are native `<button aria-pressed>` / `<input type=checkbox>` reachable by Tab with visible focus, text contrast ≥ 4.5:1 in light and dark (evaluation: a11y).
8. **Apple driver (XCUITest, iOS + macOS)** `screens/references/platform-apple.md` + `screens/templates/ScreensCatalogTests.swift`: dedicated simulator, status bar override, `simctl ui <udid> appearance`, PNG export via `TEST_RUNNER_SCREENSHOT_DIR` (topf-secret pattern), `-only-testing` filter per stale entry, UI test target added through `project.yml` + `xcodegen generate` when missing. iOS pilot `apps/topf-secret/ios` (reuse `-UITests -UITestSeed`, backend via `depends_on` if needed), macOS pilot `apps/mail-guard` (`project.yml`). → verify: PNGs for every manifest entry of both pilots in the sorted folders; iOS status bar shows 9:41.
9. **Maestro driver (Android + Capacitor)** `screens/references/platform-maestro.md` + `screens/templates/maestro-flow.yaml`; dedicated AVD, demo mode; preflight checks `maestro`, `java`, `emulator`, `adb` and reports SKIP with the install command when missing. Pilot `apps/events/native` (Capacitor 8, Android + iOS, locales de+en). → verify: Android and iOS PNGs per manifest entry, or `SKIP (tool missing: …)` with install hint.
10. **Docs.** `README.md` skill table row (lines 7-16); repo `CLAUDE.md`: Skill roster row, Commands row for `node --test screens/bin/` and `screens.mjs`, registered-agents list gets `screens-view-discoverer`, and the "repo-supplied command string" Gotcha counts `.screens/config.json` as the fourth site. → verify: `grep -n "screens" README.md CLAUDE.md` shows all four; `bash audit/bin/check-docs-claims.sh .` OK.

11. **Connect to the existing before/after rule** (user request 2026-09-24). Today the proof comes from `/delegate` Phase 3.5/5 via `audit/bin/capture-screens.sh` (one URL, dev data, no login, one state) and the global rule "wire up button / add UI → screenshot or browser proof" (`~/.claude/CLAUDE.md:79`, source file `/Users/rafael/Developer/claude/skills-personal/config/CLAUDE.md`). Changes:
    - `delegate/SKILL.md` Phase 3.5: before resolving a URL, check `.screens/config.json`. If present: `screens.mjs affected --files <mini-spec affected files>`; when it returns ids, run `screens.mjs plan` limited to those ids and capture any that are stale (so "before" reflects HEAD), then copy their PNGs into `.claude/screenshots/before/` keeping the catalog filename. When it returns none, fall through to the existing target order. Without `.screens/`, behavior is unchanged.
    - `delegate/SKILL.md` Phase 5 step 6: when the before set came from `/screens`, rerun the same ids through the incremental path (`plan` → `up` → driver → `promote` → `down`), copy results into `.claude/screenshots/after/`, and describe the visual difference per pair; pairs whose PNG hash did not change are listed as "unchanged" instead of attached.
    - Global CLAUDE.md line 79 in the skills-personal source: append "; in a project with `.screens/`, the proof is the /screens before/after set of the affected entries".
    → verify: in `apps/zeit/app`, a `/delegate` task that edits one Blade view produces before/after pairs only for that view's manifest entries (count equals `screens.mjs affected` output × axes), both files exist, and the catalog PNGs are updated by the same run; in a repo without `.screens/`, `/delegate` Phase 3.5 still calls `capture-screens.sh` (`grep -n capture-screens delegate/SKILL.md` unchanged lines present).

### Delivery (evaluation: split)
One commit per stage in the skills repo (the repo pushes to `main`, no PRs): (a) steps 1-4 core, (b) steps 5-6 web + incremental, (c) step 7 marketing + index, (d) step 8 Apple, (e) step 9 Maestro, (f) steps 10-11 docs + /delegate integration. Pilot-project files are never committed by the executor; the user decides per pilot. Each stage is its own `/plan-it execute` session if the context runs long; the drift check at the top covers the hand-over.

### Affected Files
- `screens/SKILL.md`: new orchestrator
- `screens/references/config-schema.md`, `platform-web.md`, `platform-apple.md`, `platform-maestro.md`, `demo-data.md`: new
- `screens/agents/view-discoverer.md`: new worker spec
- `agents/screens-view-discoverer.md`: new registered agent definition
- `screens/bin/screens.mjs`, `screens/bin/screens.test.mjs`: new
- `screens/templates/capture.spec.ts`, `ScreensCatalogTests.swift`, `maestro-flow.yaml`, `marketing.html`, `index.html`: new
- `README.md`, `CLAUDE.md`: rows and one Gotcha sentence as in step 10
- `delegate/SKILL.md`: Phase 3.5 and Phase 5 step 6 as in step 11
- `/Users/rafael/Developer/claude/skills-personal/config/CLAUDE.md`: line 79 half-sentence (separate repo, separate commit)
- Pilot projects (`apps/zeit/app`, `apps/topf-secret/ios`, `apps/mail-guard`, `apps/events/native`): only the per-project files in the table above, `project.yml` UI-test target where missing, `.gitignore` lines for `screenshots/`, `.screens/state.json`, `.screens/.incoming/`, `.screens/.lock`, Playwright devDependency where missing.

### Conventions
- Skill body, references, agents in English; German only in `when_to_use` triggers and user-facing strings (global rule).
- No emojis, no em-dashes in any file.
- Zero npm/composer dependencies in this repo (repo `CLAUDE.md` "Stack"); Node scripts use built-ins only. Project-side dependencies (Playwright devDependency, Maestro CLI) are allowed per user decision.
- Per-project files live in `.screens/`, not `.claude/`: subagents cannot write under `.claude/` (repo `CLAUDE.md` "Key invariants"), and the scaffold executor must write drivers and seeders.
- Orchestrator writes, subagents return: the discoverer returns structured output, the orchestrator writes config/manifest.
- Worker spec vs registered agent: worker spec without frontmatter, registered definition with frontmatter (repo `CLAUDE.md` Conventions).
- Every SKILL.md Bash block is a fresh shell; values across blocks via `orch_state_save`/`orch_state_load` (repo `CLAUDE.md` Gotchas).
- Bin output contract: `KEY=value` lines plus one final result line; environment gaps (missing simulator/tool) = SKIP, exit 0 (exemplar `audit/bin/capture-screens.sh:20-23`). Safety guard failures are FAIL and stop that platform.
- `.gitignore` additions only after `git check-ignore` (exemplar `audit/bin/capture-screens.sh:24-27`).
- Subagent briefings carry output format and length cap; discoverer and scaffold executor on sonnet, never `fable`/`inherit`.
- Never read or write `.env*`. The skill never commits in the target project.

## Edge Cases
- Platform toolchain missing: SKIP that platform with install hint, continue others.
- Route with parameters (`/projects/{project}`): manifest references a stable demo record by slug set in the seeder, never by auto-increment id.
- View only reachable after a multi-step flow: manifest `steps[]` with inputs; driver replays.
- Seeder fails on first run: stop before capture, show the error, keep config/manifest, next run retries scaffold.
- Laravel config cache present, resolved DB ≠ isolated DB, pgsql isolated name without `_screens` suffix or equal to the dev DB: FAIL before any migrate (guard in step 2).
- Port in use: next free port for this run.
- Service never healthy (90 s): `down`, FAIL with last 30 log lines.
- Dynamic content: fixed clock, masks, external requests blocked.
- Dark mode unsupported: theme axis collapses to light.
- View removed from code: delta discovery removes the entry, PNGs move to `_removed/<date>/`.
- Run interrupted: platforms already promoted are kept; `.incoming/` is cleared at the next run start.
- Two runs in one repo: lock → FAIL (locked). Runs in two repos: separate dedicated devices.
- Very large manifests (events likely > 1000 PNGs): planned total shown in the first-run summary and at every run start; `/screens <platform>` for partial runs.
- Pilot has uncommitted changes: fine as long as none of the files the skill creates or edits are among them (see STOP).
- PNG hash differs although pixels look identical (encoder nondeterminism): shows up as `updated` on an unchanged run 2 in step 6; that is a STOP to reconsider the pixel decoder, not a silent tolerance.

## Known Costs
- Four platforms in v1 (simplicity challenge suggested web first; user decided all four): Maestro + Java + Android emulator become machine dependencies for Android/Capacitor, and each native app needs a demo launch path.
- Marketing renders in v1 (simplicity challenge suggested deferring; user decided v1): one more template, config section, and a headline review step.
- Byte-hash instead of pixel threshold: if an encoder turns out nondeterministic, a pixel decoder has to be added later.
- Deterministic scripted capture needs the manifest kept in sync; delta discovery covers route changes, but a new state inside an existing view (e.g. a new modal) is only found when its source file changes and the discoverer runs.
- Re-confirmation on changed commands costs one question after every config edit.

## Done Criteria
- [ ] `node --test screens/bin/` → exit 0, ≥ 17 tests
- [ ] `apps/zeit/app`: `/delegate` on one Blade view yields before/after pairs only for that view's entries
- [ ] `bash audit/bin/check-fresh-shell.sh .` → no hit under `screens/`
- [ ] `ls ~/.claude/skills/screens/SKILL.md` resolves after one session Stop (sync hook)
- [ ] `apps/zeit/app`: first run PNG count == planned count; run 2a planned=0, run 2b `--full` `updated=0`; edited-view run recaptures only that entry; dev DB row count unchanged
- [ ] `apps/zeit/app`: marketing drafts at exact store size; reviewed headline moves render out of `_draft`
- [ ] `apps/topf-secret/ios` and `apps/mail-guard`: PNGs for every manifest entry
- [ ] `apps/events/native`: Android + iOS PNGs per manifest entry in de and en for marketing entries, or `SKIP (tool missing: …)` with install hint
- [ ] `git -C <pilot> status --porcelain` shows no `.env*` change and no file outside the per-project list
- [ ] `grep -rn "—" screens/` → no matches
- [ ] Skills repo: no files outside the Affected Files list changed (`git status`, ignoring the unrelated pre-existing modifications present at `3f7a134`)

## STOP Conditions
- The current state at the named locations does not match the descriptions (codebase has drifted).
- A verify criterion fails twice after a serious fix attempt.
- The fix would need to touch an out-of-scope file.
- The Laravel DB guard cannot confirm the isolated path in a pilot (would force touching `.env`).
- `xcrun simctl boot` opens a visible window, or XCUITest cannot write to `TEST_RUNNER_SCREENSHOT_DIR` under Xcode 27.
- A pilot has uncommitted changes in a file the skill wants to create or edit.
- Step 6 run 2b (a `--full` recapture without source changes) reports any `updated` entry after the server-side fixed clock is in place (byte-hash assumption false).

## Maintenance Notes
- Xcode 27 replaced Simulator.app with Device Hub; `simctl` verified unchanged on 2026-09-16 (`audit/bin/capture-screens.sh:4-7`). Re-verify after each Xcode major.
- Reviewer: every generated driver must read the manifest at runtime instead of hard-coding entries.
- Deferred: CI usage, visual regression reports, locale axis for the whole catalog (marketing only in v1), WordPress/Local, SwiftPM-only macOS apps without an Xcode project (e.g. `apps/zeit/macos`).

## Revision log
- 2026-09-25, status: web (zeit, 56 views / 260 combos + 5 HQ marketing renders), iOS (topf-secret, 18 entries) and macOS (layer, 2 entries) captured live; Android driver implemented and unit-tested, but the only Android pilot (events/native, Capacitor) hard-codes `server.url` and a hostname check to production (`native/capacitor.config.ts:12`, `resources/js/app.js:789`), so isolated capture is impossible without app changes. User decision: web mobile captures cover events, Android removed from events' config. Skill work lives on branch `worktree-agent-a632240e63fef4b86` until merged.
- 2026-09-24, stage (f) follow-ups (orchestrator): (1) `${PROJECT_ROOT}` placeholder in manifest/config string values (launch args, fixtures), expanded by screens.mjs and all driver templates, unknown `${X}` left untouched; (2) /delegate Phase 5 decides "unchanged" pairs via promote's tolerance result, not raw sha256; (3) zeit demo seeder: no lorem ipsum, German-looking emails/domains (marketing quality); (4) remove unused params/vars flagged by tsc in screens.mjs/screens.test.mjs.
- 2026-09-24, stage (b) round G: axes expanded to 260 entries; Alpine animation race and GPU raster jitter fixed; residual AA jitter → ImageMagick tolerance in promote; capture efficiency section; device-class folders (user request).
- 2026-09-24, stage (b) STOP 3: Laravel 13 `Collection::random` uses the unseedable secure Randomizer (zeit `AdminDemoDataSeeder.php:350`), plus locale-less Faker generator and cache store: added Seeder determinism rules.
- 2026-09-24, stage (b) STOP 2: server-side `now()` broke byte determinism; added the PHP auto-prepend fixed clock (Isolation and lifecycle), split step 6 run 2 into 2a (incremental) and 2b (`--full` determinism). Pilot manifest must cover all HTML GET views, not a curated subset.
- 2026-09-24, stage (b) STOP 1: Laravel isolation was sqlite-only; zeit is Postgres-only. Guard extended to the project's own driver (pgsql branch with `_screens` suffix + distinct-from-dev check). Plan SHA unchanged, stage (a) code at `fa34700` needs the pgsql branch before step 5.

## Challenge Result (2026-09-24)
Consolidation: 15 concerns → 12 after dedupe, plus 2 orchestrator findings.
- Convergent: headline review gate (Product + Design) → incorporated (Marketing review gate, index marketing section).
- Convergent: PNG decoder risk (Simplicity: remove; Architecture: harden) → incorporated as byte-hash, decoder dropped.
- Incorporated: Laravel DB guard incl. config cache (Risk, Critical); lockfiles in `global_sources` + `--full` (Risk); trust re-confirm on changed commands (Risk); promote per platform (Architecture); dedicated simulator/AVD (Architecture); first-run summary lists hero screens (Design); filterable index.html (Design); primary-locale detection + marketing locales (Product); `/screens <platform>` (Product).
- Dropped: web-only v1 and deferring marketing (Simplicity, FOR DISCUSSION): both contradict explicit user decisions; costs recorded under Known Costs.
- Evaluation (verdict: well-specified, weakness was one linear delivery): staged commits, run-ledger calls, index.html a11y verify → all incorporated.
- User addition after challenge: connect to the before/after rule → step 11.
- Orchestrator findings: pilot paths corrected to `apps/*`; existing XCUITest screenshot pattern in topf-secret → user switched iOS from Maestro to XCUITest.
