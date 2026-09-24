# Config + Manifest Schema

JSON schema (informal, not JSON Schema) for the two committed per-project files
`.screens/config.json` and `.screens/manifest.json`. Written by the orchestrator from the
discoverer's structured output (Phase 1), never by a subagent directly (repo `CLAUDE.md` "Orchestrator
writes, subagents return").

## `.screens/config.json`

```
{
  "platforms": ["web"],                    // subset of web|ios|android|macos

  "<platform>": {                          // one block per configured platform
    "framework": "laravel",                // laravel|bun|astro|ios|android|capacitor|...
    "start_command": "php artisan serve --port=<port>",
    "seed_command": "php artisan migrate:fresh --seed --seeder=ScreensDemoSeeder --force",
    "health_url": "http://127.0.0.1:<port>/",
    "port": 8734,
    "env": { "DB_CONNECTION": "sqlite", "DB_DATABASE": ".screens/web/screens.sqlite",
              "QUEUE_CONNECTION": "sync", "MAIL_MAILER": "log", "BROADCAST_DRIVER": "log" },
    "isolated_db": ".screens/web/screens.sqlite",
    "fixed_now": "2026-05-12T09:41:00+02:00", // PHP projects only: server-side fixed clock,
                                            // same instant as capture.spec.ts's FIXED_TIME (see
                                            // platform-web.md "Server-side fixed clock" and
                                            // "Faker's dateTimeBetween/dateTimeInInterval/
                                            // getMaxTimestamp also read real wall-clock time")
    "depends_on": null                     // another platform key this one's backend needs, or null
  },

  "roles": ["guest", "admin", "member"],
  "demo_logins": { "admin": "admin@screens.test", "member": "member@screens.test" },
  "demo_logins_empty": { "member": "member-empty@screens.test" }, // optional: a per-role account
                                            // seeded with no data (onboarding completed, zero
                                            // records), used for an entry whose states include
                                            // "empty"; a role without an empty-state login here
                                            // falls back to demo_logins (the entry still gets a
                                            // distinct __empty__ filename, just with filled data)
  "demo_password_empty": "password",       // optional: only needed when the empty-state account's
                                            // password differs from demo_password (e.g. it is a
                                            // project's own pre-existing secondary test user, not
                                            // one ScreensDemoSeeder created with SEED_ADMIN_PASSWORD)

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
                                            // ImageMagick is not on PATH

  "global_sources": [
    "resources/css/**", "tailwind.config.*", "composer.lock", "package-lock.json", "bun.lock",
    "Package.resolved", "gradle/libs.versions.toml",
    "database/seeders/ScreensDemoSeeder.php"
  ],
  "route_sources": ["routes/*.php", "src/pages/**", "**/*View.swift"],

  "marketing": {
    "entries": [
      { "id": "dashboard-hero", "format": "1920x1080",
        "headlines": { "de": { "text": "Alles im Blick", "reviewed": false },
                        "en": { "text": "Everything at a glance", "reviewed": false } } }
    ],
    "locales": ["de", "en"],
    "formats": { "web": "1920x1080", "ios": "1320x2868", "ipad": "2064x2752",
                 "android": "1080x1920", "macos": "2880x1800" }
  }
}
```

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
      "ready": "[data-testid=dashboard-loaded]",
      "steps": [],                         // only for views reachable via a multi-step flow
      "error_fill": [                      // only for an entry whose states include "error":
        { "selector": "input[name=email]", "value": "not-an-email" }, // {selector, value} pairs
        { "selector": "input[name=password]", "value": "wrong-password" }
      ],                                   // filled then the form is submitted so the page renders
                                            // its own real server-side validation error
      "known_nondeterministic": "row order has no ORDER BY tie-break", // optional: seeder
                                            // determinism rule (4), platform-web.md; excludes this
                                            // entry from the changed/unchanged byte-identical count
      "reload_per_viewport": false         // optional (default false): capture.spec.ts reloads this
                                            // entry per viewport instead of resizing the same page
                                            // in place (Capture efficiency); set only when verified
                                            // to differ (ImageMagick compare, platform-web.md)
    }
  ]
}
```

Output layout (Output layout section of the plan; `screens.mjs`'s `buildScreenshotPath`):
`screenshots/<platform>/<device-class>/<area>/<view>/<state>__<role>__<theme>[__<locale>].png`.
`<device-class>` comes from `axes.device_classes.<platform>[<viewport>]` (falls back to the viewport
spec itself when unmapped); the viewport therefore does not appear in the filename, only in the
folder. `screens.mjs migrate-layout` moves a pre-existing flat `<platform>/<area>/<view>/` tree into
this layout once, rewriting `state.json`'s per-entry `pngs` keys (now full paths relative to
`screenshots/`) without recapturing; run it once before the first `plan` after upgrading.

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
  "reach": "Tab: Recipes -> Recipe row 1", "states": ["filled", "empty"], "roles": ["guest"],
  "sources": ["RezepteApp/Views/RecipeDetailView.swift"], "mask": [], "ready": null }
```
