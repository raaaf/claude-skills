# Apple Driver (XCUITest, iOS + macOS)

Invoked by `/screens` `SKILL.md` Phase 5's driver step (plan step 8) when `.screens/config.json` has
an `ios` and/or `macos` platform and `screens/templates/ScreensCatalogTests.swift` has been
instantiated into the project's UI test target (Phase 2 scaffold).

## Contents

- [Setup (`screens.mjs up`)](#setup-screensmjs-up)
- [Launch-arg vocabulary reuse](#launch-arg-vocabulary-reuse)
- [XcodeGen target addition](#xcodegen-target-addition)
- [Invocation](#invocation)
- [Filtering](#filtering)
- [Determinism notes](#determinism-notes)
- [Known limits](#known-limits)

## Setup (`screens.mjs up`)

`screens.mjs up --platform ios|macos` (`deviceSetupHook` -> `iosDeviceSetup`/`macosDeviceSetup`)
does, in order:

1. **Disk guard.** `df -g <project root>` (`checkDiskGuard`); below 8 GB free reports
   `UP_RESULT=SKIP (low disk: <N> GB free, need 8)` before touching anything else (plan's "Disk
   guard", user decision "Sparmodus": derivedDataPath and simulator work are the two disk-heavy
   steps here).
2. **iOS only -- find-or-create the dedicated simulator.** Name is deterministic per repo:
   `screens-<repoHash>-<deviceClass>` (`simulatorNameForDevice`, `repoHash` = sha256 of the
   absolute project root, first 8 hex chars), `deviceClass` from `config.ios.device_class` (default
   `iphone`; the pilot config lists iPhone only, no iPad, per the machine-limits decision).
   `xcrun simctl list devices -j` is checked first (`findSimulatorUdidByName`); only when no device
   with that name exists does `up` create one via `xcrun simctl create <name> <deviceType>
   <runtimeId>`, `deviceType` from `config.axes.devices.ios[0]` (default `iPhone 17 Pro`),
   `runtimeId` the newest available iOS runtime (`xcrun simctl list runtimes -j`,
   `findNewestIosRuntimeId`, sorted by dotted version). Missing `xcrun`/no available runtime is an
   environment gap, reported `SKIP`, not `FAIL` (bin output contract).
3. **iOS only -- boot headless.** `xcrun simctl boot <udid>`, never `open -a Simulator` (STOP
   condition: "xcrun simctl boot opens a visible window" -- verified not the case under Xcode 27,
   see Maintenance Notes below). Booting an already-booted device is a no-op `simctl` accepts.
4. **iOS only -- status bar override.** `xcrun simctl status_bar <udid> override --time 9:41
   --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
   (`statusBarOverrideArgs`), topf-secret's own fixed-clock convention for the status bar. Applied
   once per `up`, persists across the platform's whole run.
5. **`up` reports `SIMULATOR_UDID=<udid>`, `SIMULATOR_NAME=<name>` (iOS only),
   `DERIVED_DATA_PATH=.screens/.build/<platform>` and `PROJECT_ROOT=<absolute path>`.** The
   derivedDataPath is per-run, gitignored, deleted in `down` (disk guard): never the shared
   `~/Library/Developer/Xcode/DerivedData`. `PROJECT_ROOT` is forwarded as
   `TEST_RUNNER_SCREENS_PROJECT_ROOT` so `ScreensCatalogTests.swift` can expand a `${PROJECT_ROOT}`
   placeholder in manifest/config values itself.

**Appearance (light/dark) is NOT set by `up`.** It is set once per `xcodebuild` invocation, before
running that theme's tests (see Invocation below): `xcrun simctl ui <udid> appearance light|dark`
(`appearanceArgs`). Setting it inside `up` would only ever capture one theme per run.

`down --platform ios|macos`: `xcrun simctl shutdown <udid>` (re-derives the udid from the same
deterministic name via `findSimulatorUdidByName`, no state needed to remember it), then deletes
`.screens/.build/<platform>`. The simulator itself is never deleted (`simctl delete`), only shut
down: `up` reuses it on the next run (plan's "Dedicated devices").

macOS has no simulator step at all (plan "Isolation and lifecycle": "macOS: no device"); `up` only
runs the disk guard and reports the derivedDataPath.

## Launch-arg vocabulary reuse

The scaffold does not invent a parallel seed vocabulary. `config.ios.launch_args_prefix` (default
`["-UITests"]`) and `config.ios.seed_flag` (default `"-UITestSeed"`) mirror
`UITestLauncher.launchApp`'s own convention (topf-secret: `-UITests` is the master switch to an
in-memory store, `-UITestSeed <scenario>` picks a named fixture). A manifest entry's `seeds` map
(`{"filled": "library5", "empty": "empty"}`) picks the scenario per state; a state with no matching
key launches with no seed flag (the app's own default/empty state). `config.ios.fixed_date`
(optional, e.g. `"2026-05-12T09:41:00Z"`) is appended as `-ScreensFixedDate <value>` only when the
app supports it (Isolation and lifecycle: "-ScreensFixedDate 2026-05-12T09:41:00Z"); when the
discoverer finds no such launch-arg support, it leaves `fixed_date` unset and instead lists the
date-dependent views for a `mask[]` entry, same treatment as a web view with no clock seam
(`platform-web.md`).

## XcodeGen target addition

When the project has no UI test target, the Phase 2 scaffold adds one via `project.yml` +
`xcodegen generate`, following `RezepteAppUITests`'s own shape (`apps/topf-secret/ios/project.yml`):
`type: bundle.ui-testing`, `dependencies: [{ target: <AppTarget> }]`, `TEST_TARGET_NAME:
<AppTarget>`, `GENERATE_INFOPLIST_FILE: YES`, added to the app's scheme under `test.targets`. The
target is named `<App>ScreensUITests` to stay distinct from an existing hand-written UI test target
(e.g. `RezepteAppUITests`) rather than adding `ScreensCatalogTests.swift` into it, unless the project
already has one target the discoverer confirms is safe to extend (topf-secret: `RezepteAppUITests`
already exists and is extended directly, per the plan's pilot instruction, since it already carries
the shared `UITestLauncher` helper this template does not depend on).

## Invocation

From the project root, after `screens.mjs up --platform ios|macos` reported `UP_RESULT=OK`:

```
cd <project root>
for THEME in light dark; do   # only the themes config.axes.themes lists
  xcrun simctl ui "$SIMULATOR_UDID" appearance "$THEME"   # iOS only; macOS follows system appearance
  TEST_RUNNER_SCREENS_MANIFEST_PATH="$(pwd)/.screens/manifest.json" \
  TEST_RUNNER_SCREENS_CONFIG_PATH="$(pwd)/.screens/config.json" \
  TEST_RUNNER_SCREENS_ENTRIES="<comma-separated stale entry ids>" \
  TEST_RUNNER_SCREENSHOT_DIR="$(pwd)/.screens/.incoming/<platform>" \
  TEST_RUNNER_SCREENS_THEME="$THEME" \
  TEST_RUNNER_SCREENS_VIEWPORT_ID="<device class, e.g. iphone|mac>" \
  TEST_RUNNER_SCREENS_PROJECT_ROOT="<up's PROJECT_ROOT output line>" \
  nice -n 10 xcodebuild test \
    -project <App>.xcodeproj -scheme <Scheme> \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -only-testing:<UITestTarget>/ScreensCatalogTests
done
```

macOS drops `-destination` (runs on the host directly) and the `simctl ui` line; its `-scheme` is
the macOS scheme. `TEST_RUNNER_*` env vars are forwarded into the test process by Xcode's own
`TEST_RUNNER_` prefix convention (the same mechanism `ScreenshotTourTests.swift`'s
`SCREENSHOT_DIR`/`SCREENSHOT_VARIANT` already rely on): Xcode strips the `TEST_RUNNER_` prefix
before the test process sees the variable, so `ScreensCatalogTests.swift` reads `SCREENS_MANIFEST_PATH`,
not `TEST_RUNNER_SCREENS_MANIFEST_PATH` (verified against a real `xcodebuild test` run on the
topf-secret pilot: the prefixed name is invisible inside the test process, only the stripped one
resolves).

## Filtering

`-only-testing` only selects whole test methods, and `ScreensCatalogTests` is one method that loops
over every manifest entry internally (reading the manifest at runtime, repo CLAUDE.md "Reviewer"
note) -- so the per-entry filter for a stale-only incremental run is the env list
`TEST_RUNNER_SCREENS_ENTRIES` (comma-separated ids from `screens.mjs plan`'s `PLAN_ENTRY <id>
{new|stale|missing_png}` lines, skip `unchanged`), read inside the test and applied before the
per-entry loop runs, not `-only-testing` narrowing test methods. `-only-testing` still selects the
one test method itself, scoping the whole run to `ScreensCatalogTests` and skipping any other UI
test class in the same target (e.g. topf-secret's own `ScreenshotTourTests`,
`CookFlowTests`, ...).

## Determinism notes

- Fixed status bar (9:41, full battery/signal) covers the same non-deterministic chrome the web
  driver's `page.clock.setFixedTime` covers for wall-clock display; app-level "now" needs
  `-ScreensFixedDate` support in the app itself (Launch-arg vocabulary reuse above), same limitation
  class as the web driver's server-side fixed clock.
- Named seed scenarios (`UITestLauncher.Seed`-style) are the native equivalent of the web driver's
  demo seeder: a fixed scenario name resolves to the same fixture data every run, no faker/random
  seeding to manage on the native side.
- Animations are not globally disabled the way Playwright's CSS override does; the `perform(steps:)`
  0.8s settle (same margin as `ScreenshotTourTests.shot`) is the only guard against a mid-transition
  capture. An entry whose transition regularly exceeds that margin needs a `wait` step targeting the
  destination's final state before the implicit settle, not a longer global sleep.

## Known limits

- No `mask[]` equivalent for native views: a date-dependent view without `-ScreensFixedDate` support
  is listed by the discoverer for manual review rather than silently captured with live timestamps
  (Launch-arg vocabulary reuse above).
- The `perform(steps:)` vocabulary (`tap_tab`/`tap`/`wait`/`type`/`swipe_up`/`swipe_down`) covers the
  navigation shapes seen in the topf-secret/mail-guard pilots; a view reachable only through a gesture
  outside this vocabulary (e.g. a drag-to-reorder) is out of scope for stage d and stays
  screenshot-less until the vocabulary grows.
- iPhone only in the pilot config (`config.axes.devices.ios`), no iPad simulator (machine-limits
  decision, "Sparmodus"); a project needing iPad screenshots adds a second `device_class` entry
  later, the driver code already reads `device_class` per platform block rather than assuming one.

## Maintenance note (Xcode 27)

Xcode 27 replaced Simulator.app with Device Hub; `audit/bin/capture-screens.sh:4-7` verified `xcrun
simctl` (list, boot, io screenshot) unchanged on 2026-09-16. This stage additionally verified
`simctl create`, `simctl status_bar override`, and `simctl ui appearance` against the same Xcode 27
toolchain (`xcrun simctl boot` does not raise Device Hub or any visible window -- confirmed with a
booted-but-not-foregrounded device, matching the capture-screens.sh precedent). Re-verify after each
Xcode major, per the plan's Maintenance Notes.
