# Config + Manifest Schema

JSON schema (informal, not JSON Schema) for the two committed per-project files
`.screens/config.json` and `.screens/manifest.json`. Written by the orchestrator from the
discoverer's structured output (Phase 1), never by a subagent directly (repo `CLAUDE.md` "Orchestrator
writes, subagents return").

## Contents

- [`.screens/config.json`](#screensconfigjson)
- [`.screens/manifest.json`](#screensmanifestjson)
- [Example: Laravel entry (web)](#example-laravel-entry-web)
- [Example: iOS entry (native)](#example-ios-entry-native)

## `.screens/config.json`

```
{
  "platforms": ["web"],                    // subset of web|ios|android|macos

  "output_dir": null,                      // optional override for the PNG catalog root (never the
                                            // config/manifest/state/secrets, which always stay under
                                            // this project's own `.screens/`). Supports `~` and
                                            // `${PROJECT_ROOT}` expansion. Unset (the default): the
                                            // catalog lives under `~/Developer/screens/<project>/`.
  "project": null,                         // slug for `~/Developer/screens/<project>/` (see
                                            // "Output root" below); written automatically on first
                                            // run when unset -- normally never set by hand.

  "<platform>": {                          // one block per configured platform
    "framework": "laravel",                // laravel|bun|astro|ios|android|capacitor|...
    "start_command": "php artisan serve --port=<port>",
    "seed_command": "php artisan migrate:fresh --seed --seeder=ScreensDemoSeeder --force",
    "health_url": "http://127.0.0.1:<port>/",
    "port": 8734,
    "env": { "DB_CONNECTION": "sqlite", "DB_DATABASE": ".screens/web/screens.sqlite",
              "QUEUE_CONNECTION": "sync", "MAIL_MAILER": "log", "BROADCAST_DRIVER": "log" },
    "isolated_db": ".screens/web/screens.sqlite",
    "secret_env_aliases": ["SEED_ADMIN_PASSWORD"], // optional, names only (values never
                                            // appear here, see "Demo password" below):
                                            // `up` also sets each listed name to the demo
                                            // password, for a project whose own seeder env
                                            // var isn't called DEMO_USER_PASSWORD; the
                                            // secret guard checks key names in `web.env`
                                            // only, so this field is exempt by construction
    "fixed_now": "2026-05-12T09:41:00+02:00", // PHP projects only: server-side fixed clock,
                                            // same instant as capture.spec.ts's FIXED_TIME (see
                                            // platform-web.md "Server-side fixed clock" and
                                            // "Faker's dateTimeBetween/dateTimeInInterval/
                                            // getMaxTimestamp also read real wall-clock time")
    "depends_on": null                     // another platform key this one's backend needs, or null
  },

  "ios": {                                 // stage d: XCUITest, no "framework"/"start_command"/
                                            // "seed_command" (native launch args replace them)
    "device_class": "iphone",              // simulator device-class key (plan's machine-limits
                                            // decision: iPhone only, no iPad, in the pilot config);
                                            // simulator name is `screens-<repoHash>-<device_class>`
    "launch_args_prefix": ["-UITests"],    // reused launch-arg vocabulary (Launch-arg vocabulary
                                            // reuse, screens/references/platform-apple.md), mirrors
                                            // the project's own UITestLauncher-style master switch
    "seed_flag": "-UITestSeed",            // flag name for a manifest entry's per-state seed
                                            // scenario (entry `seeds` map, see manifest below)
    "fixed_date": null,                    // optional, e.g. "2026-05-12T09:41:00Z": appended as
                                            // "-ScreensFixedDate <value>" only when the app supports
                                            // it; unset entries with date-dependent content get a
                                            // discoverer note instead (native has no mask[])
    "system_prompts": "allow"              // "allow"|"deny", default "allow": which button
                                            // ScreensCatalogTests.swift taps on a system TCC
                                            // permission prompt (camera/local network/contacts/...)
                                            // that appears before a capture (platform-apple.md
                                            // "System permission prompts")
  },
  "macos": {                               // stage d: no simulator (plan "macOS: no device"),
                                            // otherwise the same block shape as ios minus device_class
    "launch_args_prefix": ["-UITests"],
    "seed_flag": "-UITestSeed",
    "fixed_date": null,
    "system_prompts": "allow"
  },

  "android": {                              // stage e: Maestro, plain Android or a Capacitor app's
                                            // Android build (screens/references/platform-maestro.md)
    "device_class": "android-phone",       // AVD name is `screens_<repoHash>_<device_class>`
    "device_profile": "pixel_6",           // optional, avdmanager `-d` device profile (default pixel_6,
                                            // the profile already installed/verified on this machine)
    "app_id": "de.rafaelalex.events",      // Capacitor appId / Android applicationId (maestro flow header)
    "login_selectors": {                   // optional: overrides the Breeze/Jetstream default ids
      "email": "email", "password": "password", "submit": "password"
    },
    "build_dirs": [                        // deleted in `down` (Disk guard; Gradle has no
                                            // -derivedDataPath-equivalent redirect flag, platform-maestro.md
                                            // "Known limits")
      "native/android/app/build", "native/android/build"
    ],
    "depends_on": "web"                    // declarative only (not yet auto-started, same as ios/macos):
                                            // a Capacitor app's backend isolation runs through the "web"
                                            // block's own guard/seed/serve, platform-maestro.md
                                            // "Capacitor backend isolation"
  },

  "roles": ["guest", "admin", "member"],
  "demo_logins": { "admin": "admin@screens.test", "member": "member@screens.test" },
  "demo_logins_empty": { "member": "member-empty@screens.test" }, // optional: a per-role account
                                            // seeded with no data (onboarding completed, zero
                                            // records), used for an entry whose states include
                                            // "empty"; a role without an empty-state login here
                                            // falls back to demo_logins (the entry still gets a
                                            // distinct __empty__ filename, just with filled data)
                                            // NOTE: no password field lives here -- see
                                            // "Demo password (secrets.local.json)" below. `up`
                                            // FAILs if this file has a `demo_password` key.

  "axes": {
    "viewports": { "web": ["1440x900", "390x844"] },
    "devices": { "ios": ["iPhone 17 Pro", "iPad Pro 13\""], "android": ["Pixel 9"] },
    "themes": ["light"],                   // ["light", "dark"] only when the discoverer found dark-mode support
    "locales": { "primary": "de", "marketing": ["de", "en"] },
    "device_classes": {                    // viewport -> device-class folder name (Output layout);
      "web": { "1440x900": "desktop", "390x844": "mobile" } // an unmapped viewport falls back to itself
    }
  },

  "diff_tolerance": 0.0001,                // promote: keep the old PNG when ImageMagick `compare
                                            // -metric AE -fuzz 2%` reports at most this fraction of
                                            // the image area differing (default 0.01%, revised
                                            // 2026-09-24: headless Chromium font AA jitters 1-100 px
                                            // across runs even with --disable-gpu); byte-exact when
                                            // ImageMagick is not on PATH. Under `--full`, an entry
                                            // whose fingerprint did NOT change but whose PNG still
                                            // differs beyond this tolerance is written (truth wins)
                                            // and counted as `drift`, not `changed` -- the source is
                                            // provably unchanged, so this is render/encoder
                                            // nondeterminism the tolerance did not catch, reported
                                            // separately instead of hidden inside "updated"

  "global_sources": [
    "resources/css/**", "tailwind.config.*", "composer.lock", "package-lock.json", "bun.lock",
    "Package.resolved", "gradle/libs.versions.toml",
    "database/seeders/ScreensDemoSeeder.php"
  ],
  "route_sources": ["routes/*.php", "src/pages/**", "**/*View.swift"],

  "marketing": {
    "entries": [
      { "id": "dashboard-hero", "format": "1920x1080", "layout": "browser-phone",
        "headlines": { "de": { "text": "Alles im Blick", "reviewed": false },
                        "en": { "text": "Everything at a glance", "reviewed": false } } }
    ],
    "locales": ["de", "en"],
    "formats": { "web": "1920x1080", "ios": "1320x2868", "ipad": "2064x2752",
                 "android": "1080x1920", "macos": "2880x1800" },
    "layout": "browser",                   // global default: "browser" (a cropped macOS-style
                                            // browser window) or "browser-phone" (browser + an
                                            // overlapping iPhone frame); an entry's own "layout"
                                            // overrides this default
    "domain": "app.example.com",           // shown in the browser mockup's URL pill; a project
                                            // without a real production domain on file (never read
                                            // from .env) falls back to a placeholder
    "source_scale": 2                      // default 2: capture.spec.ts additionally captures every
                                            // marketing entry's desktop + mobile combo (filled state,
                                            // light theme) at deviceScaleFactor 2 into
                                            // .screens/.marketing-src/<id>__desktop.png /
                                            // <id>__mobile.png, bypassing promote so the catalog PNGs
                                            // never change; the marketing render's browser/phone
                                            // mockups downsample from these instead of the 1x catalog
                                            // PNG (findMarketingSourceSet, resolveEntrySources).
                                            // Either file missing falls back to the 1x catalog source
                                            // and, for the mobile file specifically, downgrades a
                                            // "browser-phone" entry to plain "browser"
  }
}
```

## Demo password (`.screens/secrets.local.json`)

No demo password lives in `config.json`, a manifest, or any generated driver file (security fix:
no demo password in any repo). `screens.mjs up`'s seed step creates
`<project>/.screens/secrets.local.json` the first time it runs on a machine:

```
{
  "demo_password": "<24 random URL-safe chars>",
  "demo_password_empty": "password"        // optional: only needed when the empty-state account's
                                            // password differs from demo_password (e.g. it is a
                                            // project's own pre-existing secondary test user, not
                                            // one ScreensDemoSeeder created)
}
```

- Gitignored (`up` adds `/.screens/secrets.local.json` to `.gitignore` the first time it writes the
  file), mode 0600.
- Created once per machine, then reused verbatim on every later run -- never regenerated while the
  file exists.
- Rotate it by deleting it together with the isolated DB (a DB seeded under the old password is
  useless once the password changes).
- Passed to the seed and serve commands as `DEMO_USER_PASSWORD`, in addition to `config.web.env`;
  the project's own demo seeder reads `DEMO_USER_PASSWORD` from the environment and throws when it
  is empty (no hardcoded fallback).
- `<platform>.secret_env_aliases` (names only, see above) sets each listed name to the same value
  too (`demoPasswordEnv`), so a project whose own seeder reads a differently named env var (e.g.
  `SEED_ADMIN_PASSWORD`) does not need its source edited to also read `DEMO_USER_PASSWORD`. The
  secret guard (below) only scans `web.env` key names, so listing a PASSWORD-like name inside
  `secret_env_aliases` is exempt by construction: it holds names, never values.
- `capture.spec.ts`, `generate-maestro-flows.mjs` and `ScreensCatalogTests.swift` (native has no
  password login) all read the same file at runtime instead of `config.demo_password`.
- `up` FAILs before doing anything else if `config.json` has a `demo_password` key, or if any
  `config.web.env` key looks like a secret (matches `/PASSWORD|SECRET|TOKEN/i`).

## `.screens/manifest.json`

```
{
  "entries": [
    {
      "id": "dashboard",
      "platform": "web",
      "area": "app",
      "view": "dashboard",
      "reach": "/dashboard",               // URL (web) or XCUITest nav path / Maestro steps (native)
      "states": ["empty", "filled", "error"],
      "roles": ["admin", "member"],
      "sources": ["resources/views/dashboard.blade.php", "app/Livewire/Dashboard.php"],
      "mask": [".timestamp"],              // CSS selectors hidden before capture
      "ready": "[data-testid=dashboard-loaded]", // CSS selector, waited via Playwright's
                                            // waitForSelector (web) / entry.ready fallback (Maestro)
      "ready_text": "Dashboard loaded",    // optional: visible-text readiness match instead of/in
                                            // addition to `ready` (web: Playwright's getByText,
                                            // exact: false; Maestro: its native text assertion,
                                            // preferred over `ready` there when both are set) --
                                            // for a view with no data-testid to select on
      "steps": [],                         // only for views reachable via a multi-step flow
      "error_fill": [                      // only for an entry whose states include "error":
        { "selector": "input[name=email]", "value": "not-an-email" }, // {selector, value} pairs
        { "selector": "input[name=password]", "value": "wrong-password" }
      ],                                   // filled then the form is submitted so the page renders
                                            // its own real server-side validation error
      "known_nondeterministic": "row order has no ORDER BY tie-break", // optional: seeder
                                            // determinism rule (4), platform-web.md; excludes this
                                            // entry from the changed/unchanged byte-identical count
      "reload_per_viewport": false,        // optional (default false): capture.spec.ts reloads this
                                            // entry per viewport instead of resizing the same page
                                            // in place (Capture efficiency); set only when verified
                                            // to differ (ImageMagick compare, platform-web.md)
      "seeds": {                           // ios/macos only: per-state seed scenario name, passed as
        "filled": "library5"               // `<seed_flag> <value>` (config's ios/macos block); a
                                            // state with no key here launches with no seed flag
      }
    }
  ]
}
```

**Output root**: every catalog PNG (and `index.html`/`catalog.json`/`_marketing/`/`_removed/`) lives
under a resolved output root, never inside the project itself -- `config.output_dir` (`~` and
`${PROJECT_ROOT}` expand) when set, else `~/Developer/screens/<project>/`. `<project>` is
`config.project` when set, else derived from the `~/Developer/apps/<name>/...` directory convention
(`resolveScreensOutputRoot`/`deriveProjectSlug` in `screens.mjs`) -- NOT from git, since a project's
own platform subprojects are routinely independent git repos (verified live: `zeit/app` and
`zeit/macos` are two separate repos, and a git-based slug would split one product's catalog into
two). A family with more than one `.screens` root (several platform subprojects) gets the subpath
appended (`myapp-ios`), a single-platform family (`zeit/app`, `topf-secret/ios`) keeps the bare
family name (`zeit`, `topf-secret`); a `.screens` root outside `~/Developer/apps/` falls back to its
own directory name. The derived slug is written into `config.project` on first run so it stays
stable across a repo move/rename. `.screens/config.json`, `manifest.json`, `state.json`,
`secrets.local.json` and every driver file always stay in the project's own `.screens/`, never in
the output root. `screens.mjs migrate-output` moves an existing project-local `screenshots/` tree
into the resolved output root once (byte-for-byte, verified via a sha256 sample), then removes the
now-empty `screenshots/` dir; a `screenshots/` entry left in `.gitignore` afterwards is harmless.
`screens.mjs index` also regenerates `~/Developer/screens/index.html`, a static table of every
project that has a `catalog.json` there (name, platforms, image count, last run, relative link to
that project's own `index.html`).

Marketing output layout (`screens.mjs`'s `marketingTargetDir`, added stage c), relative to the
output root: `_marketing/[_draft/]<platform>/<locale>/<format>/<NN>-<id>.png` -- an unreviewed
headline (`headlines.<locale>.reviewed: false`) routes under `_draft`; `<NN>` is the entry's 1-based
position in `marketing.entries`, zero-padded to 2 digits. `screens.mjs marketing` re-renders an
entry x locale only when its source catalog PNG hash, headline text, or review state changed since
the last render (state keyed `<id>__<locale>__<format>` in `.screens/state.json`'s `marketing`
object); a review-state flip also deletes the stale file at the old (draft/reviewed) path.

Output layout (Output layout section of the plan; `screens.mjs`'s `buildScreenshotPath`), relative
to the output root:
`<platform>/<device-class>/<area>/<view>/<state>__<role>__<theme>[__<locale>].png`.
`<device-class>` comes from `axes.device_classes.<platform>[<viewport>]` (falls back to the viewport
spec itself when unmapped); the viewport therefore does not appear in the filename, only in the
folder. `screens.mjs migrate-layout` moves a pre-existing flat `<platform>/<area>/<view>/` tree into
this layout once, rewriting `state.json`'s per-entry `pngs` keys (now full paths relative to the
output root) without recapturing; run it once before the first `plan` after upgrading.

**`${PROJECT_ROOT}` placeholder**: a manifest/config string value (`launch_args`, `extra_args`,
`steps[]` inputs, a fixture path, `env` values passed to a driver) may use `${PROJECT_ROOT}` instead
of an absolute path baked in at discovery time; it expands to the absolute directory containing
`.screens/`. `screens.mjs` expands it once (`expandProjectRoot`, applied to the whole platform
config block in `up`); the driver templates that read the manifest themselves at runtime
(`capture.spec.ts`, `generate-maestro-flows.mjs`, own JS equivalents; `ScreensCatalogTests.swift` via
the `SCREENS_PROJECT_ROOT` env var forwarded through `TEST_RUNNER_SCREENS_PROJECT_ROOT`,
`platform-apple.md` "Invocation") expand it the same way. An unknown `${X}` placeholder is left
untouched.

`sources[]` and `global_sources` are globs matched against repo-relative paths
(`screens/bin/screens.mjs`'s `matchesGlob`: `**` any depth, `*` no `/`, `?` one char). A route with
parameters resolves via a stable demo record by slug set in the seeder, never by auto-increment id
(Edge Cases).

## Example: Laravel entry (web)

```json
{ "id": "invoice-detail", "platform": "web", "area": "billing", "view": "invoice-detail",
  "reach": "/invoices/demo-invoice-1", "states": ["filled", "error"], "roles": ["member"],
  "sources": ["resources/views/billing/invoice-detail.blade.php", "app/Http/Controllers/InvoiceController.php"],
  "mask": [".issued-at"], "ready": "[data-testid=invoice-total]" }
```

## Example: iOS entry (native)

```json
{ "id": "recipe-detail", "platform": "ios", "area": "recipes", "view": "RecipeDetailView",
  "reach": "Tab: Recipes -> Recipe row 1", "states": ["filled"], "roles": ["guest"],
  "sources": ["RezepteApp/Views/RecipeDetailView.swift"],
  "seeds": { "filled": "library5" },
  "steps": [
    { "action": "tap_tab", "label": "Rezepte" },
    { "action": "wait", "label": "Rote Linsensuppe" },
    { "action": "tap", "label": "Rote Linsensuppe" }
  ] }
```

Native `steps[]` (ios/macos, `screens/templates/ScreensCatalogTests.swift`) use a small generic
vocabulary instead of the web driver's CSS selectors: `tap_tab`/`tap`/`wait`/`type` (match by
accessibility-label prefix, or by exact `id` -- accessibility identifier -- when the step carries an
`id` field instead of `label`, e.g. `{"action": "tap", "id": "cookButton"}`) plus
`swipe_up`/`swipe_down`; `type` also takes a `text` field; `tap`/`wait` also take `"optional":
"true"` to shorten the wait to 2s and continue instead of stalling 10s on an affordance that may not
be present (e.g. an advance-loop step past the flow's last screen). An entry may also set
`launch_args` (full launch-argument override, replaces `launch_args_prefix` + seed entirely, for a
flow with its own master switch such as `-UITestWelcome`) or `extra_args` (appended after the normal
prefix + seed args, e.g. `-UITestReviewState`). Detail and known limits:
`screens/references/platform-apple.md` "Known limits".
