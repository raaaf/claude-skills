# Maestro Driver (Android + Capacitor)

Invoked by `/screens` `SKILL.md` Phase 5's driver step (plan step 9) when `.screens/config.json` has
an `android` platform block and `screens/templates/generate-maestro-flows.mjs` +
`screens/templates/maestro-flow.yaml` have been instantiated into the project (Phase 2 scaffold).
Covers both a plain Android app and a Capacitor app's Android build (XCUITest drives webviews
poorly, per the plan's Approach; Maestro's webview support covers both cases with the same flow
vocabulary). Capacitor iOS is out of scope for this driver (`platform-apple.md` covers native iOS;
a Capacitor iOS webview needs the same Maestro-over-XCUITest reasoning, not built in this stage).

## Contents

- [Setup (`screens.mjs up`)](#setup-screensmjs-up)
- [SDK and tool resolution](#sdk-and-tool-resolution)
- [Preflight](#preflight)
- [Flow generation](#flow-generation)
- [Capacitor backend isolation](#capacitor-backend-isolation)
- [Invocation](#invocation)
- [Determinism notes](#determinism-notes)
- [Known limits](#known-limits)

## Setup (`screens.mjs up`)

`screens.mjs up --platform android` (`deviceSetupHook` -> `androidDeviceSetup`, then `cmdUp`'s
generic start-command/pidfile block, then an Android-specific boot-wait + demo-mode block) does, in
order:

1. **Disk guard.** Same `checkDiskGuard` as the Apple driver, `SKIP (low disk: <N> GB free, need 8)`
   below 8 GB free (machine-limits decision, "Sparmodus").
2. **Preflight** (`androidToolsPreflight`, see below): `maestro`, `java`, the `emulator` binary, `adb`,
   and `avdmanager` must all be present; the first missing one reports `SKIP (...)` with its install
   command, no partial setup attempted.
3. **Find-or-create the dedicated AVD.** Name is deterministic per repo: `screens_<repoHash>_<deviceClass>`
   (`androidAvdName`, underscored per the plan's own naming -- `screens-<repoHash>-<device>` for
   Apple is hyphenated, a different convention, not a typo), `deviceClass` from
   `config.android.device_class` (default `android-phone`). `avdmanager list avd -c` is checked first
   (`avdExists`, exact line match); only when no AVD with that name exists does `up` create one via
   `avdmanager create avd -n <name> -k <systemImagePackage> -d <deviceProfile>` (`androidAvdCreateShellCmd`,
   piping `echo no` past the "create custom hardware profile?" prompt). `systemImagePackage` comes
   from `findInstalledSystemImages` (a real filesystem scan of `<sdkRoot>/system-images/`, newest API
   level first) -- **never downloaded**: an empty result is `SKIP` with the `sdkmanager` install
   command, per "no downloads without reporting first". `deviceProfile` defaults to `pixel_6` (the
   profile the machine's own pre-existing `events_repro` AVD already verifies installed and working);
   `config.android.device_profile` overrides it. The user's own `events_repro` AVD is never read,
   modified, or reused -- name derivation guarantees a distinct AVD every time.
4. **Boot headless.** The emulator start command (`-avd <name> -no-window -no-audio -no-boot-anim -gpu
   swiftshader_indirect -port <port>`, `androidDeviceSetup`'s `startCommand`) is handed to `cmdUp`'s
   existing generic `start_command`/pidfile spawn block (the same one a web project's `artisan serve`
   uses) instead of a parallel Android-only spawn path, so `down`'s existing generic pidfile kill
   already tears it down for free. `port` is `androidEmulatorPort(repoHash)`, a deterministic even
   port in 5554-5680 -- never the emulator's own auto-picked port, so the serial (`emulator-<port>`)
   is known without an `adb devices` round trip. `-gpu swiftshader_indirect` (software rendering) was
   chosen over a hardware host GPU path for headless CI-style stability on a machine already under
   load (Sparmodus); re-measure if boot time becomes a bottleneck.
5. **Boot-wait + demo mode.** Once the process is spawned, `cmdUp` polls `adb -s <serial> shell getprop
   sys.boot_completed` (`waitForAndroidBoot`, same 90s budget as the web health check) and then runs
   `androidDemoModeArgs(serial)`'s six `adb shell` calls in order: `sysui_demo_allowed 1` first (the
   system ignores demo broadcasts sent before this), then `enter`, then the fixed clock (9:41),
   battery (100%, not charging), network (full wifi + mobile bars), and notifications (hidden) demo
   broadcasts -- the Android equivalent of the iOS status-bar override, applied once per `up`.
6. **`up` reports `ANDROID_AVD_NAME=<name>` and `ANDROID_SERIAL=<serial>`.**

`config.android.depends_on` (config-schema.md) is declarative only, same as the Apple driver's own
`depends_on` field (neither is auto-started by `screens.mjs` yet): a Capacitor app's `web` platform
block needs its own `up` already run and healthy before the android platform loop starts (Phase 5's
per-platform order, `SKILL.md`).

**Theme (light/dark) is NOT set by `up`.** `androidThemeArgs(serial, theme)` (`adb shell cmd uimode
night yes|no`) is a per-themed-pass switch the driver applies before each themed `maestro test` run,
same reasoning as the Apple driver's `simctl ui appearance` staying out of `up`.

`down --platform android`: `adb -s <serial> emu kill` (graceful shutdown, re-derives the serial from
the same deterministic port, no state needed to remember it), then the generic pidfile kill as a
fallback/cleanup, then any `config.android.build_dirs` entries are deleted (Build output cleanup
below). The AVD itself is never deleted (plan "Dedicated devices": "AVD kept").

## SDK and tool resolution

`platform-tools`/`emulator`/`cmdline-tools` are not on `PATH` on a typical install (only
`~/.maestro/bin/maestro` is added to `PATH` by its own installer). `resolveAndroidSdkRoot(env, homeDir)`
resolves, in order: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `<homeDir>/Library/Android/sdk`.
`androidToolPaths(sdkRoot)` composes `platform-tools/adb`, `emulator/emulator`, and
`cmdline-tools/latest/bin/avdmanager` under it. `sdkmanager` is resolved the same way when a project
needs it directly, but `screens.mjs` itself never invokes `sdkmanager` (system images are discovered
from disk, never installed, see step 3 above).

## Preflight

`androidToolsPreflight(present)` is pure over a `{maestro, java, emulator, adb, avdmanager}` presence
map (real detection in `probeAndroidTools`, injectable so tests never spawn `which`/touch the real
filesystem) and reports the first missing tool with its install command:

- `maestro`: `curl -Ls "https://get.maestro.mobile.dev" | bash`
- `java`: `brew install openjdk@17` (JDK 17, matching this machine's verified
  `/Library/Java/JavaVirtualMachines/jdk-17.jdk`)
- `emulator`/`adb`: install the Android SDK's `emulator` package / `platform-tools`
- `avdmanager`: `sdkmanager "cmdline-tools;latest"` (verified missing on this machine at stage e time:
  `~/Library/Android/sdk` has `emulator`/`platform-tools`/`system-images` but no `cmdline-tools`
  directory at all -- a real, reported environment gap, not a hypothetical branch)

## Flow generation

Maestro flow YAML has no data-loop construct over an external manifest the way a Playwright `test()`
loop or a Swift `for entry in manifest.entries` can iterate at runtime, so `screens/templates/maestro-flow.yaml`
plays the role of a per-(entry, state, role) TEMPLATE rather than a single generic driver file: the
Phase 2 scaffold instantiates it verbatim into `.screens/android/maestro-flow.yaml`, alongside
`screens/templates/generate-maestro-flows.mjs` verbatim into `.screens/android/generate-maestro-flows.mjs`.
The generator reads `.screens/config.json` + `.screens/manifest.json` at RUN time (repo CLAUDE.md
"Reviewer" note: the manifest is read at runtime, not hard-coded -- by the generator, exactly as
`capture.spec.ts` and `ScreensCatalogTests.swift` read it at their own runtime), maps each entry's
`steps[]` (same `tap_tab`/`tap`/`wait`/`type`/`swipe_up`/`swipe_down` vocabulary as the Apple driver,
config-schema.md) to Maestro commands, and writes one instantiated flow YAML per (entry, state, role)
into `.screens/.maestro-generated/` -- ephemeral, cleared and rewritten on every call, never
committed, the same relationship `.screens/.incoming/<platform>/` PNGs have to the catalog. This is a
deliberate refinement of the plan's "`.screens/maestro/*.yaml`, one per manifest entry" for Maestro's
actual per-file (not per-entry-with-internal-loop) execution model; a hand-authored, entry-count-many
set of committed YAML files would drift from the manifest the same day someone edits `steps[]` without
regenerating them, which is exactly the failure mode the "read the manifest at runtime" rule exists to
prevent.

Login steps (`loginStepsFor`) reuse the Laravel login form's own input ids (Breeze/Jetstream default
`id="email"`/`id="password"`), the same selectors `capture.spec.ts`'s `loginAs()` targets via CSS --
Capacitor wraps the Laravel web UI (plan step 3 context), so the webview renders the identical form.
`config.android.login_selectors` overrides the ids when a project's form differs.

An entry with a `reach` URL (the common case, same field web entries already use) deep-links
straight there via Maestro's `- openLink:` instead of simulated taps (verified against the events
pilot: `android/app/src/main/AndroidManifest.xml` carries a verified App Link intent-filter,
`android:autoVerify="true"`), far more deterministic than a tap sequence and, unlike `steps[]`, works
unmodified for any entry with a stable URL. `config.android.base_url` (default `http://10.0.2.2:<web
port>`, the Android emulator's own alias for the host machine, never `127.0.0.1`) is prepended.
Entries with no `reach` (a view only reachable through a UI flow with no direct route) fall back to
`steps[]`. `entry.ready` holds visible TEXT for an android/capacitor entry (matched via Maestro's
`extendedWaitUntil: visible: text:`), not a CSS selector the way a web entry's `ready` does -- the
same convention the pilot's own hand-written `.maestro/*.yaml` flows already use exclusively (text/
accessibility matching, never an id, per that file's own header comment on webview robustness).

## Capacitor backend isolation

A Capacitor app's `server.url` (`capacitor.config.ts`) is read once by `npx cap sync android` and
baked into a GENERATED, gitignored artifact: `android/app/src/main/assets/capacitor.config.json`
(verified against `apps/events/native`: `android/.gitignore:88` ignores exactly this path, the same
"build cache, not source" class as Laravel's `bootstrap/cache/config.php`). The scaffold never edits
`capacitor.config.ts` (plan step 9's STOP condition: "do not change app source"); instead, AFTER `npx
cap sync android` regenerates that JSON from the real `server.url`, the driver overwrites its
`server.url` field with the isolated backend, e.g. `http://10.0.2.2:<port>` -- `10.0.2.2` is the
Android emulator's own documented alias for the host machine's `localhost`, not `127.0.0.1` (the
emulator is a separate network namespace) -- before `./gradlew assembleDebug`/`installDebug`. This
keeps the isolation guard's own scope (never touch `.env*`, never touch project source) intact while
still redirecting the app: the file it edits is regenerated from scratch by the next real `cap sync`
a developer runs, exactly like an Xcode derivedData artifact.

## Invocation

From the project root, after `screens.mjs up --platform android` reported `UP_RESULT=OK`:

```
cd <project root>
npx cap sync android
node -e "const p='android/app/src/main/assets/capacitor.config.json'; \
  const c=JSON.parse(require('fs').readFileSync(p)); \
  c.server.url='http://10.0.2.2:<isolated backend port>'; \
  require('fs').writeFileSync(p, JSON.stringify(c));"
cd android && nice -n 10 ./gradlew assembleDebug -PbuildDir=... && cd ..
adb -s "$ANDROID_SERIAL" install -r android/app/build/outputs/apk/debug/app-debug.apk

for THEME in light dark; do   # only the themes config.axes.themes lists
  adb -s "$ANDROID_SERIAL" shell cmd uimode night $([ "$THEME" = dark ] && echo yes || echo no)
  node .screens/android/generate-maestro-flows.mjs "<comma-separated stale entry ids>" "$THEME"
  nice -n 10 maestro --device "$ANDROID_SERIAL" test .screens/.maestro-generated/
  # `takeScreenshot: <name>` writes <name>.png to the project ROOT (verified
  # against the events pilot's own pre-existing .gitignore comment), not an
  # arbitrary path -- move this pass's PNGs into the incoming dir. Matched
  # by the `__<theme>` suffix the generator's own 3rd arg embeds in every
  # name it writes this call, so the glob only ever picks up this run's
  # own output, never a leftover from an unrelated `*.png` in the root.
  for f in *"__${THEME}.png"; do
    [ -f "$f" ] && mv "$f" ".screens/.incoming/android/$f"
  done
done
```

Gradle has no `-derivedDataPath`-equivalent flag that redirects `build/` without a `build.gradle`
edit (Known limits below); the plain default output path is used and removed in `down` via
`config.android.build_dirs` (e.g. `["native/android/app/build", "native/android/build"]`) instead of
being redirected under `.screens/.build/android` the way the Apple driver's derivedDataPath is.

## Determinism notes

- System UI demo mode (9:41, full battery/signal, notifications hidden) covers the same
  non-deterministic chrome the web driver's `page.clock.setFixedTime` and the Apple driver's status
  bar override cover; app-level "now" needs the same `-ScreensFixedDate`-class support the Apple
  driver documents, or a `mask[]`-equivalent (Known limits below).
- No animation-disable mechanism exists for a webview the way Playwright's injected CSS does; the
  `extendedWaitUntil: visible` step before `takeScreenshot` is the only guard against a
  mid-transition capture, same class of guard as the Apple driver's fixed settle window.

## Known limits

- **No `mask[]` equivalent inside a webview.** Maestro's `runScript` can call into a webview-exposed
  JS hook when the app defines one (`window.screensApplyMask`), but the generator emits nothing when
  no such hook exists (documented, not silently attempted) -- same "no mask equivalent" limitation
  class the Apple driver already carries for native views.
- **Gradle build output is not redirectable without a `build.gradle` edit.** Unlike Xcode's
  `-derivedDataPath`, there is no CLI flag that moves `android/app/build/` elsewhere; `down` deletes
  `config.android.build_dirs` instead of the Apple driver's redirect-then-delete pattern (Disk guard,
  Invocation above).
- **`avdmanager` was not installed on the machine this stage was implemented on** (`~/Library/Android/sdk`
  has `emulator`/`platform-tools`/`system-images` but no `cmdline-tools`), so `androidDeviceSetup`'s
  find-or-create path is verified by unit test (`screens.test.mjs`, injected runner + probe) and by a
  real `screens.mjs up --platform android` run against the events pilot reporting the correct `SKIP
  (avdmanager not found; install: sdkmanager "cmdline-tools;latest")` line, but not by an actual
  device boot + Maestro capture. Re-verify the AVD create/boot/demo-mode sequence and the flow
  generation's real Maestro-CLI behavior (in particular `takeScreenshot`'s exact output path
  resolution) once `cmdline-tools` is installed, per "no downloads without reporting first".
- Login selectors assume Laravel Breeze/Jetstream default input ids; a project with a different login
  form sets `config.android.login_selectors`.
