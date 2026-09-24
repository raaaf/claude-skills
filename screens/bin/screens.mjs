#!/usr/bin/env node
//
// screens.mjs: deterministic CLI backing the /screens skill.
//
// Node >=20, built-ins only (see audit/bin/compute-floor.mjs for the same
// convention: no npm, no package.json in this repo).
//
// Subcommands: plan, up, down, promote, marketing, index, trust, affected.
// Each subcommand emits `KEY=value` lines and, from the second-to-last
// point on, one final `SCREENS_RESULT=OK|SKIP (reason)|FAIL (reason)`-style
// result line per the bin output contract (audit/bin/capture-screens.sh
// header): environment gaps are SKIP, safety guard failures are FAIL, both
// exit 0 so the calling skill can branch on the text instead of the exit
// code. Every function below is exported so screens.test.mjs can call it
// directly (in particular the Laravel/Bun DB guards, which take an
// injectable command runner instead of always spawning `php`/real
// commands, per the plan's testability requirement).
//
// Per-project files this CLI reads/writes all live under `.screens/` and
// `screenshots/` in the TARGET project (never under `.claude/`, see repo
// CLAUDE.md "Per-project files live in .screens/, not .claude/").

import {
  readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync,
  rmSync, renameSync,
} from 'node:fs';
import { join, dirname, relative, resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync, spawn, execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import os from 'node:os';

// ---------------------------------------------------------------------
// Generic JSON + glob helpers
// ---------------------------------------------------------------------

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(path, obj) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(obj, null, 2) + '\n');
}

function argValue(args, flag) {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
}

// Minimal glob support: `**` (any depth, incl. `/`), `*` (no `/`), `?`
// (one char, no `/`), everything else literal. No npm glob dependency.
function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        re += '.*';
        i++;
        if (glob[i + 1] === '/') i++;
      } else {
        re += '[^/]*';
      }
    } else if (c === '?') {
      re += '[^/]';
    } else if ('.+^${}()|[]\\'.includes(c)) {
      re += '\\' + c;
    } else {
      re += c;
    }
  }
  return new RegExp('^' + re + '$');
}

function matchesGlob(path, glob) {
  return globToRegExp(glob).test(path);
}

const EXCLUDED_DIRS = new Set(['.git', 'node_modules', '.screens', 'screenshots']);

function listRepoFiles(root) {
  const out = [];
  (function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (EXCLUDED_DIRS.has(entry.name)) continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(relative(root, full));
    }
  })(root);
  return out;
}

function resolveGlobs(root, globs, allFiles) {
  const files = allFiles || listRepoFiles(root);
  const matched = new Set();
  for (const g of globs) {
    for (const f of files) if (matchesGlob(f, g)) matched.add(f);
  }
  return [...matched].sort();
}

// sha256 over the sorted set of matched source + global_sources file paths
// and their contents. Deterministic: same files, same bytes -> same hash.
function computeFingerprint(root, sources, globalSources) {
  const files = listRepoFiles(root);
  const paths = resolveGlobs(root, [...(sources || []), ...(globalSources || [])], files);
  const hash = createHash('sha256');
  for (const p of paths) {
    hash.update(p);
    try {
      hash.update(readFileSync(join(root, p)));
    } catch {
      // unreadable file: contributes its path only, never fatal
    }
  }
  return hash.digest('hex');
}

// `pngs` keys are full paths relative to `screenshots/` (device-class layout,
// Output layout section) since the migrate-layout pass; a legacy entry that
// still carries `dir` is resolved through it so `plan` stays correct before
// `migrate-layout` has run.
function entryPngsExist(root, entryState) {
  if (!entryState || !entryState.pngs) return false;
  return Object.keys(entryState.pngs).some((f) => {
    const rel = entryState.dir ? join(entryState.dir, f) : f;
    return existsSync(join(root, 'screenshots', rel));
  });
}

function listDirFiles(root, relDir) {
  const out = [];
  (function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(relative(root, full));
    }
  })(join(root, relDir));
  return out;
}

// ---------------------------------------------------------------------
// plan
// ---------------------------------------------------------------------

function planEntries(root, manifest, state, full) {
  const config = readJson(join(root, '.screens/config.json'), {});
  const globalSources = config.global_sources || [];
  const results = [];
  for (const entry of manifest.entries || []) {
    const fingerprint = computeFingerprint(root, entry.sources || [], globalSources);
    const prev = state.entries && state.entries[entry.id];
    let status;
    if (!prev) status = 'new';
    else if (fingerprint !== prev.fingerprint) status = 'stale';
    else if (full) status = 'stale';
    else if (!entryPngsExist(root, prev)) status = 'missing_png';
    else status = 'unchanged';
    results.push({ id: entry.id, status, fingerprint });
  }
  return results;
}

function cmdPlan(args, root = process.cwd()) {
  const lines = [];
  const full = args.includes('--full');
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  const results = planEntries(root, manifest, state, full);
  let planned = 0;
  let skipped = 0;
  for (const r of results) {
    lines.push(`PLAN_ENTRY ${r.id} ${r.status}`);
    if (r.status === 'unchanged') skipped++;
    else planned++;
  }
  const manifestIds = (manifest.entries || []).map((e) => e.id);
  const removedIds = Object.keys(state.entries || {}).filter((id) => !manifestIds.includes(id));
  for (const id of removedIds) lines.push(`PLAN_REMOVED ${id}`);
  lines.push(`SCREENS_RESULT=OK planned=${planned} skipped=${skipped} removed=${removedIds.length}`);
  return lines;
}

// ---------------------------------------------------------------------
// up / down: generic lifecycle driven entirely by config.json
// ---------------------------------------------------------------------

// A crashed run leaves `.screens/.lock` behind forever, FAILing every later
// `up`. If the PID recorded in the lock file is no longer alive
// (`process.kill(pid, 0)` throws ESRCH), the lock is stale: remove it, emit
// `LOCK=STALE_REMOVED`, and report unlocked. An unparsable PID (e.g. from an
// older lock format) or a PID whose liveness can't be confirmed (EPERM: a
// process exists but is owned by someone else) is treated conservatively as
// still locked.
function checkLock(root) {
  const lockPath = join(root, '.screens/.lock');
  if (!existsSync(lockPath)) return false;
  const pid = parseInt(readFileSync(lockPath, 'utf8').trim(), 10);
  if (pid) {
    try {
      process.kill(pid, 0);
      return true;
    } catch (err) {
      if (err && err.code === 'ESRCH') {
        rmSync(lockPath, { force: true });
        console.log('LOCK=STALE_REMOVED');
        return false;
      }
      return true;
    }
  }
  return true;
}

function defaultRunner(cmd, args, env) {
  const res = spawnSync(cmd, args, { env: { ...process.env, ...env }, encoding: 'utf8' });
  return { stdout: res.stdout || '', status: res.status };
}

// ---------------------------------------------------------------------
// Apple device setup (iOS + macOS, stage d). Android/Maestro (stage e)
// keeps reporting the honest "not implemented yet" SKIP below.
// ---------------------------------------------------------------------

// Deterministic per-repo simulator name (plan "Dedicated devices"):
// `screens-<repo-hash>-<device>`, stable across runs of the same repo so
// `up` can find-or-create instead of creating a new device every time.
function repoHash(root) {
  return createHash('sha256').update(resolve(root)).digest('hex').slice(0, 8);
}

function simulatorNameForDevice(hash, deviceClass) {
  return `screens-${hash}-${deviceClass}`;
}

// `df -g <path>` header + one data row; the 4th column is "Available"
// (1G-blocks Used Available Capacity ...). Pure parse, no spawn, so the
// disk-guard branch is directly testable.
function parseDfAvailableGb(stdout) {
  const lines = (stdout || '').trim().split('\n');
  if (lines.length < 2) return null;
  const cols = lines[1].trim().split(/\s+/);
  const gb = parseInt(cols[3], 10);
  return Number.isNaN(gb) ? null : gb;
}

// Disk guard (plan "Disk guard", user decision "Sparmodus"): SKIP below
// 8 GB free on the volume that holds the pilot, checked before any
// derived-data build or simulator work starts. An unparsable `df` output
// fails open (never blocks a run on a parsing quirk); a crossed threshold
// mid-run is the caller's responsibility to re-check (Phase 5 loop, one
// platform at a time).
function checkDiskGuard(root, runner = defaultRunner) {
  const res = runner('df', ['-g', root], {});
  const freeGb = parseDfAvailableGb(res.stdout);
  if (freeGb === null) return { ok: true, freeGb: null };
  return { ok: freeGb >= 8, freeGb };
}

// Shared "SKIP below 8 GB free" early-return shape, extracted once it
// tripled across `iosDeviceSetup`/`macosDeviceSetup`/`androidDeviceSetup`
// (same duplicated 2-line guard, three device-setup functions). Returns
// the skip object to return-early with, or `null` when disk is fine.
function diskGuardSkip(root, runner) {
  const disk = checkDiskGuard(root, runner);
  if (disk.ok) return null;
  return { ok: true, skip: true, reason: `SKIP (low disk: ${disk.freeGb} GB free, need 8)` };
}

// `xcrun simctl list runtimes -j` -> newest available iOS runtime
// identifier, sorted by dotted version number. Pure over the parsed JSON.
function findNewestIosRuntimeId(runtimesJson) {
  let parsed;
  try {
    parsed = JSON.parse(runtimesJson);
  } catch {
    return null;
  }
  const candidates = (parsed.runtimes || []).filter(
    (r) => r.isAvailable && /\.iOS-/.test(r.identifier || ''),
  );
  if (!candidates.length) return null;
  candidates.sort((a, b) => {
    const av = (a.version || '0').split('.').map(Number);
    const bv = (b.version || '0').split('.').map(Number);
    for (let i = 0; i < Math.max(av.length, bv.length); i++) {
      const diff = (av[i] || 0) - (bv[i] || 0);
      if (diff) return diff;
    }
    return 0;
  });
  return candidates[candidates.length - 1].identifier;
}

// `xcrun simctl list devices -j` -> udid of a device with the given name
// (any runtime bucket), or null when no such device exists yet (reuse
// check, plan "Dedicated devices": "reused across runs, never the user's
// currently booted device").
function findSimulatorUdidByName(devicesJson, name) {
  let parsed;
  try {
    parsed = JSON.parse(devicesJson);
  } catch {
    return null;
  }
  for (const bucket of Object.values(parsed.devices || {})) {
    for (const d of bucket) if (d.name === name) return d.udid;
  }
  return null;
}

// `simctl status_bar ... override` argument composition (topf-secret's own
// fixed 9:41 convention, plan step 8): pure so the composed command is
// testable without spawning `xcrun`.
function statusBarOverrideArgs(udid) {
  return [
    'simctl', 'status_bar', udid, 'override',
    '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100',
    '--cellularBars', '4', '--wifiBars', '3',
  ];
}

function appearanceArgs(udid, theme) {
  return ['simctl', 'ui', udid, 'appearance', theme];
}

// Finds-or-creates the dedicated simulator, boots it headless (never `open
// -a Simulator`, STOP condition: "xcrun simctl boot opens a visible
// window"), and applies the fixed status bar. Appearance (light/dark) is
// NOT set here: it is a per-theme, per-xcodebuild-invocation step the
// driver runs before each themed test pass (`screens/references/platform-apple.md`).
function iosDeviceSetup(root, config, runner = defaultRunner) {
  const diskSkip = diskGuardSkip(root, runner);
  if (diskSkip) return diskSkip;

  const iosConfig = config.ios || {};
  const deviceClass = iosConfig.device_class || 'iphone';
  const name = simulatorNameForDevice(repoHash(root), deviceClass);

  const listRes = runner('xcrun', ['simctl', 'list', 'devices', '-j'], {});
  let udid = findSimulatorUdidByName(listRes.stdout, name);

  if (!udid) {
    const runtimesRes = runner('xcrun', ['simctl', 'list', 'runtimes', '-j'], {});
    const runtimeId = findNewestIosRuntimeId(runtimesRes.stdout);
    // Missing xcrun/no iOS runtime is an environment gap, not a safety-guard
    // failure (bin output contract): SKIP, not FAIL.
    if (!runtimeId) return { ok: true, skip: true, reason: 'no available iOS runtime found (xcrun simctl list runtimes)' };
    const deviceType = (config.axes && config.axes.devices && config.axes.devices.ios && config.axes.devices.ios[0])
      || 'iPhone 17 Pro';
    const createRes = runner('xcrun', ['simctl', 'create', name, deviceType, runtimeId], {});
    udid = (createRes.stdout || '').trim();
    if (!udid) return { ok: true, skip: true, reason: `simctl create failed for "${name}" (${deviceType}, ${runtimeId})` };
  }

  runner('xcrun', ['simctl', 'boot', udid], {});
  runner('xcrun', statusBarOverrideArgs(udid), {});

  return { ok: true, skip: false, udid, name };
}

// macOS runs the app directly (no simulator, plan "Isolation and
// lifecycle": "macOS: no device"); only the disk guard applies.
function macosDeviceSetup(root, runner = defaultRunner) {
  const diskSkip = diskGuardSkip(root, runner);
  if (diskSkip) return diskSkip;
  return { ok: true, skip: false };
}

// ---------------------------------------------------------------------
// Android device setup (Maestro, stage e). SDK resolution + dedicated AVD,
// mirroring the Apple find-or-create/reuse shape above but for
// avdmanager/adb instead of simctl.
// ---------------------------------------------------------------------

// `screens_<repoHash>_<deviceClass>` (plan step 1: pinned per-repo AVD
// name), underscored per the plan's own naming, unlike the iOS
// `screens-<hash>-<device>` hyphenated form.
function androidAvdName(hash, deviceClass = 'android-phone') {
  return `screens_${hash}_${deviceClass}`;
}

// Deterministic emulator console port per repo (even, 5554-5680, the
// documented AVD console-port range) so two repos never collide and a
// rerun always targets the same serial without an adb enumeration round
// trip. A real collision (another emulator already bound to that port,
// e.g. the user's own `events_repro`) surfaces as an emulator start
// failure, same class as a `simctl create` failure above.
function androidEmulatorPort(hash) {
  const n = parseInt(hash.slice(0, 4), 16) % 64;
  return 5554 + n * 2;
}

// SDK resolution (plan: "platform-tools/adb NOT on PATH: resolve via
// ANDROID_HOME/ANDROID_SDK_ROOT or ~/Library/Android/sdk"). Pure over the
// passed env + home dir so the fallback chain is directly testable.
function resolveAndroidSdkRoot(env = process.env, homeDir = os.homedir()) {
  return env.ANDROID_HOME || env.ANDROID_SDK_ROOT || join(homeDir, 'Library/Android/sdk');
}

function androidToolPaths(sdkRoot) {
  return {
    adb: join(sdkRoot, 'platform-tools', 'adb'),
    emulator: join(sdkRoot, 'emulator', 'emulator'),
    avdmanager: join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager'),
  };
}

// Preflight (plan step 9: "preflight checks maestro, java, emulator, adb
// and reports SKIP with the install command when missing"). Pure over a
// presence map so the check order is directly testable without touching
// the filesystem; `probeAndroidTools` below does the real existsSync/
// commandOnPath calls.
function androidToolsPreflight(present) {
  if (!present.maestro) return { ok: false, reason: 'maestro not found; install: curl -Ls "https://get.maestro.mobile.dev" | bash' };
  if (!present.java) return { ok: false, reason: 'java not found; install JDK 17 (e.g. brew install openjdk@17)' };
  if (!present.emulator) return { ok: false, reason: 'android emulator not found; install the Android SDK "emulator" package' };
  if (!present.adb) return { ok: false, reason: 'adb not found; install Android SDK platform-tools' };
  if (!present.avdmanager) return { ok: false, reason: 'avdmanager not found; install: sdkmanager "cmdline-tools;latest"' };
  return { ok: true };
}

function probeAndroidTools(sdkRoot) {
  const tools = androidToolPaths(sdkRoot);
  return {
    maestro: commandOnPath('maestro') || existsSync(join(os.homedir(), '.maestro/bin/maestro')),
    java: commandOnPath('java') || existsSync('/Library/Java/JavaVirtualMachines/jdk-17.jdk'),
    emulator: existsSync(tools.emulator),
    adb: existsSync(tools.adb),
    avdmanager: existsSync(tools.avdmanager),
  };
}

// AVD reuse (plan step 1 "AVD name derivation, reuse"): `avdmanager list
// avd -c` prints one AVD name per line, nothing else -- exact match
// against the deterministic name, same shape as `findSimulatorUdidByName`'s
// JSON parse above but for a plain-text list.
function avdExists(listAvdOutput, name) {
  return (listAvdOutput || '').split('\n').map((l) => l.trim()).includes(name);
}

// Installed system images (no `sdkmanager` on this machine to list them,
// see stage e context): scans `<sdkRoot>/system-images/<api>/<tag>/<abi>`
// and returns `system-images;<api>;<tag>;<abi>` package ids, newest API
// level first. Real fs walk (like `listRepoFiles` above), never downloads
// anything -- an empty result is a SKIP with the install command, per "no
// downloads without reporting first".
function findInstalledSystemImages(sdkRoot) {
  const base = join(sdkRoot, 'system-images');
  const out = [];
  let apis;
  try {
    apis = readdirSync(base, { withFileTypes: true }).filter((e) => e.isDirectory());
  } catch {
    return out;
  }
  for (const apiEntry of apis) {
    let tags;
    try {
      tags = readdirSync(join(base, apiEntry.name), { withFileTypes: true }).filter((e) => e.isDirectory());
    } catch {
      continue;
    }
    for (const tagEntry of tags) {
      let abis;
      try {
        abis = readdirSync(join(base, apiEntry.name, tagEntry.name), { withFileTypes: true }).filter((e) => e.isDirectory());
      } catch {
        continue;
      }
      for (const abiEntry of abis) {
        out.push(`system-images;${apiEntry.name};${tagEntry.name};${abiEntry.name}`);
      }
    }
  }
  out.sort((a, b) => {
    const an = parseInt((/android-(\d+)/.exec(a) || [])[1] || '0', 10);
    const bn = parseInt((/android-(\d+)/.exec(b) || [])[1] || '0', 10);
    return bn - an;
  });
  return out;
}

// AVD create: `echo no |` answers avdmanager's "create custom hardware
// profile? [no]" prompt (same shell-wrapped-command reasoning as the
// seed/view:cache calls in `cmdUp` below). Device profile defaults to
// "pixel_6", the profile `events_repro.avd`'s own config.ini already
// verifies installed and working on this machine; a project needing a
// different profile sets `config.android.device_profile`.
function androidAvdCreateShellCmd(avdmanagerPath, name, systemImagePackage, deviceProfile = 'pixel_6') {
  return `echo no | "${avdmanagerPath}" create avd -n "${name}" -k "${systemImagePackage}" -d "${deviceProfile}"`;
}

// System UI demo mode (plan step 1): fixed clock 9:41, full battery, full
// network, notifications hidden -- the Android equivalent of the iOS
// status bar override, applied once per `up` (`sysui_demo_allowed` must be
// set before the first demo broadcast or the system ignores it).
function androidDemoModeArgs(serial) {
  const base = ['-s', serial, 'shell'];
  return [
    [...base, 'settings', 'put', 'global', 'sysui_demo_allowed', '1'],
    [...base, 'am', 'broadcast', '-a', 'com.android.systemui.demo', '--es', 'command', 'enter'],
    [...base, 'am', 'broadcast', '-a', 'com.android.systemui.demo', '--es', 'command', 'clock', '--es', 'hhmm', '0941'],
    [...base, 'am', 'broadcast', '-a', 'com.android.systemui.demo', '--es', 'command', 'battery', '--es', 'level', '100', '--es', 'plugged', 'false'],
    [...base, 'am', 'broadcast', '-a', 'com.android.systemui.demo', '--es', 'command', 'network', '--es', 'wifi', 'show', '--es', 'level', '4', '--es', 'mobile', 'show', '--es', 'datatype', 'none', '--es', 'level', '4'],
    [...base, 'am', 'broadcast', '-a', 'com.android.systemui.demo', '--es', 'command', 'notifications', '--es', 'visible', 'false'],
  ];
}

// Theme (plan step 1: "theme via adb shell cmd uimode night yes|no"). Not
// applied by `androidDeviceSetup`/`up` (same reasoning as `appearanceArgs`
// above: it's a per-themed-pass switch the driver applies before each run,
// see `platform-maestro.md`), exported for that use.
function androidThemeArgs(serial, theme) {
  return ['-s', serial, 'shell', 'cmd', 'uimode', 'night', theme === 'dark' ? 'yes' : 'no'];
}

// `adb shell getprop sys.boot_completed` polling, the Android equivalent of
// `waitForHealth` above (same 90s budget as the web health check and the
// STOP-condition-adjacent iOS boot, though iOS's `simctl boot` call itself
// blocks until booted and needs no polling).
function waitForAndroidBoot(adbPath, serial, timeoutSec, runner = defaultRunner) {
  const start = Date.now();
  while ((Date.now() - start) / 1000 < timeoutSec) {
    const res = runner(adbPath, ['-s', serial, 'shell', 'getprop', 'sys.boot_completed'], {});
    if ((res.stdout || '').trim() === '1') return true;
    try {
      execSync('sleep 2');
    } catch {
      // ignore
    }
  }
  return false;
}

// Finds-or-creates the dedicated AVD (never `events_repro`, the user's own
// device: the name is always `screens_<repoHash>_<deviceClass>`), and
// returns the `nice`-free emulator start command for `cmdUp`'s generic
// start_command/pidfile spawn block to run (reused rather than duplicated,
// see that block's own comment). Boot-wait + demo mode happen in `cmdUp`
// once the process is actually running, not here (parallel to how iOS's
// `simctl boot` call is synchronous but the appearance/theme switch is a
// separate per-pass step the driver owns).
// `probe` is injectable (default `probeAndroidTools`, real existsSync/
// commandOnPath calls) so a test can fix the tool-presence map instead of
// depending on what happens to be installed on the machine running the
// suite (same "runner injected" testability requirement as the rest of
// this file's device-setup functions).
function androidDeviceSetup(root, config, runner = defaultRunner, probe = probeAndroidTools) {
  const diskSkip = diskGuardSkip(root, runner);
  if (diskSkip) return diskSkip;

  const androidConfig = config.android || {};
  const sdkRoot = resolveAndroidSdkRoot();
  const tools = androidToolPaths(sdkRoot);
  const preflight = androidToolsPreflight(probe(sdkRoot));
  if (!preflight.ok) return { ok: true, skip: true, reason: preflight.reason };

  const hash = repoHash(root);
  const deviceClass = androidConfig.device_class || 'android-phone';
  const name = androidAvdName(hash, deviceClass);
  const port = androidEmulatorPort(hash);
  const serial = `emulator-${port}`;

  const listRes = runner(tools.avdmanager, ['list', 'avd', '-c'], {});
  if (!avdExists(listRes.stdout, name)) {
    const images = findInstalledSystemImages(sdkRoot);
    if (!images.length) {
      return {
        ok: true, skip: true,
        reason: `no Android system image installed under ${sdkRoot}/system-images (install: sdkmanager "system-images;android-<api>;google_apis;arm64-v8a")`,
      };
    }
    const createCmd = androidAvdCreateShellCmd(tools.avdmanager, name, images[0], androidConfig.device_profile);
    const createRes = runner('sh', ['-c', createCmd], {});
    if (createRes.status !== 0) return { ok: true, skip: true, reason: `avdmanager create avd failed for "${name}" (${images[0]})` };
  }

  const startCommand = `"${tools.emulator}" -avd "${name}" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -port ${port}`;
  return { ok: true, skip: false, name, serial, port, startCommand, tools };
}

function deviceSetupHook(platform, root = process.cwd(), config = {}, runner = defaultRunner) {
  if (platform === 'android') return androidDeviceSetup(root, config, runner);
  if (platform === 'ios') return iosDeviceSetup(root, config, runner);
  if (platform === 'macos') return macosDeviceSetup(root, runner);
  return { ok: true, skip: false };
}

// Laravel DB guard (repo CLAUDE.md "Three sites run a repo-supplied
// command string" + plan's "Isolation and lifecycle" section). Checked in
// order, all hard FAIL before any migrate:
//   1. bootstrap/cache/config.php present -> env overrides are ignored.
//   2. config.web.isolated_db not set.
//   3. `php artisan db:show --json` (via the injected runner, so tests
//      never spawn php) resolves the isolation branch by the project's
//      own driver (revised 2026-09-24 after the zeit pilot STOP: zeit and
//      events are Postgres-only by design, sqlite is not an option there):
//      - sqlite: resolved path must equal isolated_db.
//      - pgsql: resolved database must equal isolated_db, isolated_db must
//        end in `_screens`, and it must differ from the database a second
//        `db:show --json` (no override env) resolves for the same project,
//        so a config that points dev itself at a `_screens` name still
//        fails. A missing database (db:show fails to connect) is created
//        once via `createdb <isolated_db>` through the injected runner,
//        then db:show is retried; a failing createdb is a FAIL that names
//        the command to run.
//      - anything else (mysql, ...): FAIL, unsupported in v1.
// Real `db:show --json` output nests the values under `platform.config`
// (verified against apps/zeit/app): {"platform":{"config":{"driver":
// "sqlite"|"pgsql",...,"database":"..."},...},"tables":[]}. Read exactly
// that path, no guessed fallback shapes.
function tryParseDbShow(stdout) {
  try {
    return JSON.parse(stdout);
  } catch {
    return null;
  }
}

function laravelDbGuard(root, config, runner = defaultRunner) {
  const cachePath = join(root, 'bootstrap/cache/config.php');
  if (existsSync(cachePath)) {
    return { ok: false, reason: 'config cache present; run php artisan config:clear' };
  }
  const env = (config.web && config.web.env) || {};
  const isolated = config.web && config.web.isolated_db;
  if (!isolated) return { ok: false, reason: 'config.web.isolated_db not set' };

  let result = runner('php', ['artisan', 'db:show', '--json'], env);
  let parsed = tryParseDbShow(result.stdout);

  // A missing pgsql database makes db:show fail to connect entirely, before
  // it can report anything: create it once and retry (only ever attempted
  // for a config that already declares pgsql isolation via the `_screens`
  // suffix, never for a sqlite path).
  if (!parsed && isolated.endsWith('_screens')) {
    const createResult = runner('createdb', [isolated], {});
    if (createResult.status !== 0) {
      return { ok: false, reason: `isolated database ${isolated} missing and createdb failed; run: createdb ${isolated}` };
    }
    result = runner('php', ['artisan', 'db:show', '--json'], env);
    parsed = tryParseDbShow(result.stdout);
  }

  if (!parsed) return { ok: false, reason: 'db:show output not parseable JSON' };
  const platformConfig = parsed.platform && parsed.platform.config;
  if (!platformConfig) {
    return { ok: false, reason: 'db:show output missing platform.config' };
  }
  const driver = platformConfig.driver;
  const database = platformConfig.database;

  if (driver === 'sqlite') {
    if (!database || resolve(root, database) !== resolve(root, isolated)) {
      return { ok: false, reason: `resolved DB path ${database} does not match isolated path ${isolated}` };
    }
    return { ok: true };
  }

  if (driver === 'pgsql') {
    if (!isolated.endsWith('_screens')) {
      return { ok: false, reason: `isolated_db "${isolated}" must end in _screens` };
    }
    if (database !== isolated) {
      return { ok: false, reason: `resolved database ${database} does not match isolated_db ${isolated}` };
    }
    const devResult = runner('php', ['artisan', 'db:show', '--json'], {});
    const devParsed = tryParseDbShow(devResult.stdout);
    const devDatabase = devParsed && devParsed.platform && devParsed.platform.config && devParsed.platform.config.database;
    if (devDatabase === database) {
      return { ok: false, reason: `isolated_db ${isolated} equals the dev database; config must not point dev at a _screens name` };
    }
    return { ok: true };
  }

  return { ok: false, reason: `unsupported database driver: ${driver} (v1 supports sqlite and pgsql)` };
}

// Bun/Hono guard: the resolved DB path env var must live inside .screens/.
function bunDbGuard(root, config) {
  const dbPath = (config.web && config.web.env && config.web.env.DATABASE_PATH) || (config.web && config.web.isolated_db);
  if (!dbPath) return { ok: false, reason: 'DATABASE_PATH not set' };
  const abs = resolve(root, dbPath);
  const screensDir = resolve(root, '.screens');
  if (abs !== screensDir && !abs.startsWith(screensDir + sep)) {
    return { ok: false, reason: `resolved DB path ${dbPath} is not inside .screens/` };
  }
  return { ok: true };
}

function waitForHealth(url, timeoutSec) {
  const start = Date.now();
  while ((Date.now() - start) / 1000 < timeoutSec) {
    const res = spawnSync('curl', ['-fsS', '-o', '/dev/null', '--max-time', '3', url], { encoding: 'utf8' });
    if (res.status === 0) return true;
    try {
      execSync('sleep 2');
    } catch {
      // ignore
    }
  }
  return false;
}

// Server-side fixed clock (revised 2026-09-24 after stage (b) STOP 2:
// dashboard aggregates read real `now()` server-side; the Playwright clock
// only fakes the browser). `php --ini`'s "Scan for additional .ini files
// in:" line is either a real directory or the literal string "(none)" when
// no scan dir is configured; PHP_INI_SCAN_DIR is colon-joined (macOS/Linux)
// so an existing scan dir keeps loading its own ini files alongside ours.
function composePhpIniScanDir(phpIniOutput, additionalDir) {
  const match = /Scan for additional \.ini files in:\s*(.*)/i.exec(phpIniOutput || '');
  // Real `php --ini` output quotes an actual path ("/opt/.../conf.d") but
  // not the "(none)" placeholder; strip surrounding quotes either way.
  const existing = match ? match[1].trim().replace(/^"(.*)"$/, '$1') : '';
  if (!existing || existing === '(none)') return additionalDir;
  return `${existing}:${additionalDir}`;
}

// Returns {} (no-op) for a non-PHP framework or when config.web.fixed_now
// is unset, so this stays inert everywhere except a PHP pilot that opted
// in. Applied to BOTH the serve and the seed/migrate env (plan's
// "Isolation and lifecycle"): child processes of `artisan serve` inherit
// env, but the seed/migrate command in `cmdUp` is a separate `runner` call
// and needs the same env explicitly.
function phpFixedClockEnv(root, config, runner = defaultRunner) {
  const platformConfig = config.web || {};
  if (platformConfig.framework !== 'laravel' || !platformConfig.fixed_now) return {};
  const phpIniDir = join(root, '.screens/web/php');
  const result = runner('php', ['--ini'], {});
  const scanDir = composePhpIniScanDir(result.stdout, phpIniDir);
  return { PHP_INI_SCAN_DIR: scanDir, SCREENS_FIXED_NOW: platformConfig.fixed_now };
}

// Capture efficiency (plan "Capture efficiency", revised 2026-09-24 after
// the user reported runs too slow / machine overloaded): a Laravel `artisan
// serve` worker pool handles the parallel Playwright workers instead of
// serializing every request through PHP's single-threaded dev server, and
// APP_DEBUG=false skips the debugbar/error-page overhead on every request.
// `view:cache` (never `config:cache`, see the Laravel DB guard) precompiles
// Blade views once per run instead of per-request.
function laravelPerfEnv(platformConfig) {
  if (platformConfig.framework !== 'laravel') return {};
  return { PHP_CLI_SERVER_WORKERS: '4', APP_DEBUG: 'false' };
}

// `min(4, floor(cores/2))`: leaves half the machine free for the PHP server
// pool + the user's own processes (plan "Capture efficiency").
function playwrightWorkers(cpuCount) {
  return Math.max(1, Math.min(4, Math.floor(cpuCount / 2)));
}

// Seed-on-change (plan "Capture efficiency"): fingerprints the files that can
// change what the demo seeder produces -- migrations, seeders, factories,
// the instantiated `.screens/web/php/*` files (fixed-clock + Faker
// determinism shims, platform-web.md), and `fixed_now` itself. `up` skips
// `migrate:fresh --seed` when this is unchanged from the last run's stored
// value and the isolated DB already exists (the Laravel DB guard already
// confirmed/created it before this runs); `--full`/`--reseed` force it.
function computeSeedFingerprint(root, config) {
  const platformConfig = config.web || {};
  const files = listRepoFiles(root);
  const globPaths = resolveGlobs(root, [
    'database/migrations/**', 'database/seeders/**', 'database/factories/**',
  ], files);
  const phpFiles = listDirFiles(root, '.screens/web/php').sort();
  const hash = createHash('sha256');
  for (const p of [...globPaths, ...phpFiles]) {
    hash.update(p);
    try {
      hash.update(readFileSync(join(root, p)));
    } catch {
      // unreadable file: contributes its path only, never fatal
    }
  }
  hash.update(String(platformConfig.fixed_now || ''));
  return hash.digest('hex');
}

function cmdUp(args, root = process.cwd(), runner = defaultRunner) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const platform = argValue(args, '--platform') || (config.platforms && config.platforms[0]);
  if (!platform) {
    lines.push('UP_RESULT=FAIL (no platform configured)');
    return lines;
  }
  lines.push(`PLATFORM=${platform}`);

  if (checkLock(root)) {
    lines.push('UP_RESULT=FAIL (locked)');
    return lines;
  }

  const device = deviceSetupHook(platform, root, config, runner);
  if (!device.ok) {
    lines.push(`UP_RESULT=FAIL (${device.reason})`);
    return lines;
  }
  if (device.skip) {
    lines.push(`UP_RESULT=SKIP (${device.reason})`);
    return lines;
  }
  if (device.udid) lines.push(`SIMULATOR_UDID=${device.udid}`);
  if (platform !== 'android' && device.name) lines.push(`SIMULATOR_NAME=${device.name}`);
  if (platform === 'android') {
    if (device.name) lines.push(`ANDROID_AVD_NAME=${device.name}`);
    if (device.serial) lines.push(`ANDROID_SERIAL=${device.serial}`);
  }
  if (platform === 'ios' || platform === 'macos') {
    // Disk guard (plan "Disk guard"): a per-run derivedDataPath under
    // `.screens/.build/<platform>`, gitignored, deleted in `down`, never
    // the shared `~/Library/Developer/Xcode/DerivedData` (Sparmodus).
    lines.push(`DERIVED_DATA_PATH=.screens/.build/${platform}`);
  }

  const platformConfig = config[platform] || {};

  if (platform === 'web') {
    const framework = platformConfig.framework;
    let guard = { ok: true };
    if (framework === 'laravel') guard = laravelDbGuard(root, config, runner);
    else if (framework === 'bun') guard = bunDbGuard(root, config);
    if (!guard.ok) {
      lines.push(`UP_RESULT=FAIL (${guard.reason})`);
      return lines;
    }
  }

  const lockPath = join(root, '.screens/.lock');
  mkdirSync(dirname(lockPath), { recursive: true });
  writeFileSync(lockPath, String(process.pid));

  const clockEnv = platform === 'web' ? phpFixedClockEnv(root, config, runner) : {};
  const perfEnv = platform === 'web' ? laravelPerfEnv(platformConfig) : {};
  const runEnv = { ...(platformConfig.env || {}), ...clockEnv, ...perfEnv };

  // `nice -n 10` on every process the skill drives here (server + view:cache
  // + seed), per the user's "machine overloaded" report (plan "Capture
  // efficiency"); the Playwright driver itself is niced by the caller
  // (screens/references/platform-web.md).
  if (platform === 'web' && platformConfig.framework === 'laravel') {
    runner('sh', ['-c', 'nice -n 10 php artisan view:cache'], runEnv);
  }

  // Android's emulator start command is device-derived (repo-hash AVD name
  // + port, `androidDeviceSetup`), not config-declared like a web
  // `start_command`; reusing this one spawn/pidfile block for both (instead
  // of a parallel Android-only spawn) is what makes `down`'s existing
  // generic pidfile kill below already cover the emulator process too.
  const startCommand = platformConfig.start_command || device.startCommand;
  if (startCommand) {
    const child = spawn(`nice -n 10 ${startCommand}`, {
      shell: true,
      cwd: root,
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, ...runEnv },
    });
    child.unref();
    const pidFile = join(root, '.screens', platform, 'pid');
    mkdirSync(dirname(pidFile), { recursive: true });
    writeFileSync(pidFile, String(child.pid));
    lines.push(`PID=${child.pid}`);
  }

  if (platformConfig.health_url) {
    if (!waitForHealth(platformConfig.health_url, 90)) {
      lines.push('UP_RESULT=FAIL (service never healthy within 90s)');
      return lines;
    }
    lines.push('HEALTH=OK');
  }

  // Android boot-wait + System UI demo mode (plan step 1), the Android
  // equivalent of the iOS status-bar override in `iosDeviceSetup` above,
  // applied once here rather than inside `androidDeviceSetup` because it
  // needs the emulator process actually running, not just spawned.
  if (platform === 'android' && device.serial) {
    if (!waitForAndroidBoot(device.tools.adb, device.serial, 90, runner)) {
      lines.push('UP_RESULT=FAIL (android emulator never reported sys.boot_completed within 90s)');
      return lines;
    }
    lines.push('BOOT=OK');
    for (const demoArgs of androidDemoModeArgs(device.serial)) runner(device.tools.adb, demoArgs, {});
    lines.push('DEMO_MODE=OK');
  }

  if (platformConfig.seed_command) {
    const full = args.includes('--full') || args.includes('--reseed');
    const seedFingerprint = platform === 'web' ? computeSeedFingerprint(root, config) : null;
    const seedState = readJson(join(root, '.screens/state.json'), {});
    const seedUnchanged = !full && seedFingerprint && seedState.seed_fingerprint === seedFingerprint;
    if (seedUnchanged) {
      lines.push('SEED=SKIP (unchanged)');
    } else {
      const seedResult = runner('sh', ['-c', `nice -n 10 ${platformConfig.seed_command}`], runEnv);
      if (seedResult.status !== 0) {
        lines.push('UP_RESULT=FAIL (seed command failed)');
        return lines;
      }
      lines.push('SEED=OK');
      if (seedFingerprint) {
        seedState.seed_fingerprint = seedFingerprint;
        writeJson(join(root, '.screens/state.json'), seedState);
      }
    }
  }

  lines.push(`PLAYWRIGHT_WORKERS=${playwrightWorkers(os.cpus().length)}`);
  lines.push('UP_RESULT=OK');
  return lines;
}

function cmdDown(args, root = process.cwd(), runner = defaultRunner) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const platform = argValue(args, '--platform') || (config.platforms && config.platforms[0]);

  // Apple lifecycle (stage d): shut the dedicated simulator down (never
  // delete it, plan "Dedicated devices": "shut down in down"), and delete
  // the per-run derivedDataPath (disk guard). macOS has no simulator, only
  // the derivedDataPath.
  if (platform === 'ios') {
    const hash = repoHash(root);
    const deviceClass = (config.ios && config.ios.device_class) || 'iphone';
    const name = simulatorNameForDevice(hash, deviceClass);
    const listRes = runner('xcrun', ['simctl', 'list', 'devices', '-j'], {});
    const udid = findSimulatorUdidByName(listRes.stdout, name);
    if (udid) runner('xcrun', ['simctl', 'shutdown', udid], {});
  }
  if (platform === 'ios' || platform === 'macos') {
    rmSync(join(root, '.screens', '.build', platform), { recursive: true, force: true });
  }

  // Android lifecycle (stage e): graceful `adb emu kill` (re-derives the
  // serial from the same deterministic port, no state needed to remember
  // it, same reasoning as the iOS udid re-derivation above), then the
  // generic pidfile kill below as a fallback/cleanup. The AVD itself is
  // never deleted (plan "Dedicated devices": "AVD kept").
  if (platform === 'android') {
    const sdkRoot = resolveAndroidSdkRoot();
    const tools = androidToolPaths(sdkRoot);
    const port = androidEmulatorPort(repoHash(root));
    runner(tools.adb, ['-s', `emulator-${port}`, 'emu', 'kill'], {});
  }

  // Build-output cleanup (Disk guard, "delete build outputs you create in
  // down"): generic over any platform block that declares `build_dirs`
  // (Gradle/Capacitor has no `-derivedDataPath`-style redirect flag without
  // a source-file change, see platform-maestro.md "Known limits", so its
  // ordinary `build/` output is deleted here instead of redirected+deleted
  // like the Apple `.screens/.build/<platform>` path above).
  const buildDirs = (config[platform] && config[platform].build_dirs) || [];
  for (const dir of buildDirs) rmSync(join(root, dir), { recursive: true, force: true });

  if (platform) {
    const pidFile = join(root, '.screens', platform, 'pid');
    if (existsSync(pidFile)) {
      const pid = parseInt(readFileSync(pidFile, 'utf8'), 10);
      if (pid) {
        try {
          process.kill(-pid, 'SIGTERM');
        } catch {
          try {
            process.kill(pid, 'SIGTERM');
          } catch {
            // process already gone
          }
        }
      }
      rmSync(pidFile, { force: true });
    }
    // Only a sqlite isolated_db is a file `down` may delete; a pgsql
    // isolated_db is a database name, reused (and reset by migrate:fresh)
    // on the next run, never dropped here (plan's "Isolation and
    // lifecycle": "down never drops the pgsql database").
    const isolatedDb = config[platform] && config[platform].isolated_db;
    if (isolatedDb && isolatedDb.endsWith('.sqlite')) {
      try {
        rmSync(join(root, isolatedDb), { force: true });
      } catch {
        // nothing to remove
      }
    }
  }

  rmSync(join(root, '.screens/.lock'), { force: true });
  lines.push('DOWN_RESULT=OK');
  return lines;
}

// ---------------------------------------------------------------------
// promote
// ---------------------------------------------------------------------

function commandOnPath(cmd) {
  const res = spawnSync('which', [cmd], { encoding: 'utf8' });
  return res.status === 0;
}

// PNG IHDR: 8-byte signature + 4-byte chunk length + 4-byte "IHDR" type,
// then width (4 bytes) at offset 16, height (4 bytes) at offset 20, both
// big-endian. No pixel decoder (plan's Approach).
function readPngDimensions(buf) {
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function defaultCompareRunner(oldPath, newPath) {
  const res = spawnSync('compare', ['-metric', 'AE', '-fuzz', '2%', oldPath, newPath, 'null:'], { encoding: 'utf8' });
  return { stderr: res.stderr || '' };
}

// `compare -metric AE` writes the differing-pixel count to stderr, plainly
// (e.g. "1234") or with a normalized ratio in parens ("1234 (0.0188)");
// either way the leading number is the AE count.
function parseAeCount(stderr) {
  const m = /^([\d.]+)/.exec((stderr || '').trim());
  return m ? parseFloat(m[1]) : NaN;
}

// Byte-hash compare: an unchanged sha256 leaves the target file untouched
// (mtime included). A differing hash is not automatically `changed`
// (revised 2026-09-24, plan's Incremental rule: headless Chromium font
// anti-aliasing jitters 1-100 px across runs): when ImageMagick `compare` is
// on PATH, keep the old file when the AE (differing-pixel count, 2% fuzz)
// is at most `diffTolerance * width * height` (config `diff_tolerance`,
// default 0.0001 = 0.01% of the image area). Without ImageMagick it stays
// byte-exact (the caller reports that via a NOTE line).
function promoteFile(incomingPath, targetPath, prevHash, opts = {}) {
  const {
    diffTolerance = 0.0001,
    hasCompare = commandOnPath('compare'),
    compareRunner = defaultCompareRunner,
  } = opts;
  const buf = readFileSync(incomingPath);
  const hash = createHash('sha256').update(buf).digest('hex');
  if (prevHash && hash === prevHash && existsSync(targetPath)) {
    return { changed: false, hash, tolerated: false };
  }
  if (prevHash && existsSync(targetPath) && hasCompare) {
    const { width, height } = readPngDimensions(buf);
    const { stderr } = compareRunner(targetPath, incomingPath);
    const ae = parseAeCount(stderr);
    const maxAe = diffTolerance * width * height;
    if (!Number.isNaN(ae) && ae <= maxAe) {
      return { changed: false, hash: prevHash, tolerated: true };
    }
  }
  mkdirSync(dirname(targetPath), { recursive: true });
  writeFileSync(targetPath, buf);
  return { changed: true, hash, tolerated: false };
}

// Device-class folders (Output layout, revised 2026-09-24, user request:
// split by capture device). `config.axes.device_classes.<platform>` maps a
// viewport spec to a class name (e.g. "1440x900" -> "desktop"); an
// unconfigured viewport falls back to itself so the folder stays stable
// instead of colliding with another class.
function deviceClassFor(config, platform, viewport) {
  const classes = (config.axes && config.axes.device_classes && config.axes.device_classes[platform]) || {};
  return classes[viewport] || viewport;
}

// Capture filenames (incoming and legacy-promoted) are
// `<state>__<role>__<viewport>__<theme>[__<locale>].png`.
function parseCaptureFilename(rest) {
  const base = rest.replace(/\.png$/, '');
  const [state, role, viewport, theme, locale] = base.split('__');
  return { state, role, viewport, theme, locale };
}

// Output layout: `<platform>/<device-class>/<area>/<view>/<state>__<role>__<theme>[__<locale>].png`
// -- the viewport moves from the filename into the device-class folder.
function buildScreenshotPath(config, entry, platform, parts) {
  const deviceClass = deviceClassFor(config, platform, parts.viewport);
  const area = entry.area || 'misc';
  const view = entry.view || entry.id;
  const localeSuffix = parts.locale ? `__${parts.locale}` : '';
  const filename = `${parts.state}__${parts.role}__${parts.theme}${localeSuffix}.png`;
  const relDir = join(platform, deviceClass, area, view);
  return { relDir, relPath: join(relDir, filename) };
}

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function moveRemovedEntries(root, manifestIds, state, dateStr = todayStr()) {
  const moved = [];
  for (const id of Object.keys(state.entries || {})) {
    if (manifestIds.includes(id)) continue;
    const entryState = state.entries[id];
    for (const relPath of Object.keys(entryState.pngs || {})) {
      const rel = entryState.dir ? join(entryState.dir, relPath) : relPath;
      const src = join(root, 'screenshots', rel);
      if (!existsSync(src)) continue;
      const dest = join(root, 'screenshots', '_removed', dateStr, rel);
      mkdirSync(dirname(dest), { recursive: true });
      renameSync(src, dest);
    }
    delete state.entries[id];
    moved.push(id);
  }
  return moved;
}

// Incoming filenames are `<entryId>__<rest>.png`, written by a driver into
// `.screens/.incoming/<platform>/` (drivers land in a later delivery stage;
// this promote step is generic over whatever a driver produces in that
// shape). `<rest>` becomes the filename inside the manifest entry's output
// directory (Output layout, plan's "Per-project files" table).
function cmdPromote(args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const platform = argValue(args, '--platform') || (config.platforms && config.platforms[0]);
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  state.entries = state.entries || {};

  const diffTolerance = typeof config.diff_tolerance === 'number' ? config.diff_tolerance : 0.0001;
  const hasCompare = commandOnPath('compare');

  const full = args.includes('--full');
  const incomingDir = join(root, '.screens/.incoming', platform || '');
  let changed = 0;
  let newCount = 0;
  let unchanged = 0;
  let tolerated = 0;
  let knownNondeterministic = 0;
  let drift = 0;
  if (existsSync(incomingDir)) {
    for (const file of readdirSync(incomingDir)) {
      if (!file.endsWith('.png') || !file.includes('__')) continue;
      const id = file.slice(0, file.indexOf('__'));
      const rest = file.slice(file.indexOf('__') + 2);
      const entry = manifest.entries.find((e) => e.id === id);
      if (!entry) continue;
      const parts = parseCaptureFilename(rest);
      const { relPath } = buildScreenshotPath(config, entry, entry.platform || platform, parts);
      const targetPath = join(root, 'screenshots', relPath);
      state.entries[id] = state.entries[id] || {};
      state.entries[id].pngs = state.entries[id].pngs || {};
      const prevHash = state.entries[id].pngs[relPath];
      const prevFingerprint = state.entries[id].fingerprint;
      const { changed: didChange, hash, tolerated: didTolerate } = promoteFile(
        join(incomingDir, file), targetPath, prevHash, { diffTolerance, hasCompare },
      );
      state.entries[id].pngs[relPath] = hash;
      // Persisted here (not just computed transiently in `plan`): without
      // this, `plan`'s `prev.fingerprint` is always undefined on the next
      // run, and every entry reports `stale` forever even with zero source
      // changes (Step 6's `run 2 -> new=0 updated=0` requirement).
      const newFingerprint = computeFingerprint(root, entry.sources || [], config.global_sources || []);
      state.entries[id].fingerprint = newFingerprint;
      // Drift reporting (step 1, `--full` only): a fingerprint that did not
      // change means the source is provably unchanged, so a PNG that still
      // differs beyond tolerance is not a stale-source recapture, it is
      // genuine drift (encoder/render nondeterminism the tolerance did not
      // catch). Truth wins: the new PNG is written like any other `changed`
      // entry (already done by `promoteFile` above), only the label and
      // count differ, so `_removed`/index/marketing all see the real file.
      const isDrift = full && prevFingerprint && prevFingerprint === newFingerprint && didChange && !didTolerate;
      // Seeder determinism rule (4), plan's "Isolation and lifecycle": a
      // view whose content is correct but whose row order isn't pinned by
      // an ORDER BY tie-break can hash differently on a byte-identical
      // reseed. That is not a promote defect and not maskable (the content
      // is right, only the order differs), so a manifest entry carrying
      // `known_nondeterministic` is reported separately and never counted
      // as `changed`/`unchanged` -- a byte-identical verify (Step 6 run 2b)
      // excludes it instead of failing on it.
      if (entry.known_nondeterministic) {
        knownNondeterministic++;
        lines.push(`PROMOTE_ENTRY ${id} known_nondeterministic (${entry.known_nondeterministic})`);
      } else if (isDrift) {
        drift++;
        lines.push(`DRIFT ${id} ${rest.replace(/\.png$/, '')}`);
      } else if (didTolerate) {
        tolerated++;
        lines.push(`PROMOTE_ENTRY ${id} tolerated`);
      } else if (didChange) {
        // `prevHash` absent (rather than merely different) means this PNG
        // was never promoted before: the index's run summary (plan step 3)
        // distinguishes a brand-new capture from a recapture of a known one.
        if (prevHash) {
          changed++;
          lines.push(`PROMOTE_ENTRY ${id} changed`);
        } else {
          newCount++;
          lines.push(`PROMOTE_ENTRY ${id} new`);
        }
      } else {
        unchanged++;
        lines.push(`PROMOTE_ENTRY ${id} unchanged`);
      }
    }
  }

  const manifestIds = manifest.entries.map((e) => e.id);
  const removed = moveRemovedEntries(root, manifestIds, state);
  for (const id of removed) lines.push(`PROMOTE_REMOVED ${id}`);

  // Persisted for `index` (plan step 3, "Top: last run summary"): index.html
  // is a separate `screens.mjs index` invocation with no other way to see
  // this run's tallies. `failed` stays 0 here -- a driver failure never
  // reaches `promote` at all (Phase 5 skips straight to `down`), so the
  // orchestrator's own report is the only place that count is known; index
  // reads whatever the orchestrator wrote last, defaulting to 0.
  state.last_run = {
    new: newCount, updated: changed, unchanged, removed: removed.length,
    drift, failed: (state.last_run && state.last_run.failed) || 0,
    date: todayStr(),
    commit: (spawnSync('git', ['-C', root, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).stdout || '').trim() || null,
  };

  writeJson(join(root, '.screens/state.json'), state);
  if (!hasCompare) lines.push('NOTE=imagemagick missing, byte-exact compare');
  lines.push(`PROMOTE_RESULT=OK changed=${changed} unchanged=${unchanged} tolerated=${tolerated} removed=${removed.length} known_nondeterministic=${knownNondeterministic} drift=${drift} new=${newCount}`);
  return lines;
}

// ---------------------------------------------------------------------
// migrate-layout: one-time move of pre-existing PNGs (flat
// `<platform>/<area>/<view>/` layout) into the device-class layout
// (Output layout), rewriting state.json's pngs keys to match. Chosen over
// doing this automatically inside `promote` (plan step 4, "your choice, say
// which") because a migration is a one-time structural move over the WHOLE
// existing tree, while `promote` only ever touches the files a driver just
// produced; folding it into `promote` would silently half-migrate a tree
// across many incremental runs instead of doing it once, deliberately.
function cmdMigrateLayout(args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  const defaultPlatform = (config.platforms && config.platforms[0]) || 'web';
  let moved = 0;
  for (const entry of manifest.entries || []) {
    const entryState = state.entries && state.entries[entry.id];
    if (!entryState || !entryState.dir || !entryState.pngs) continue;
    const oldDir = entryState.dir;
    const newPngs = {};
    for (const [filename, hash] of Object.entries(entryState.pngs)) {
      const parts = parseCaptureFilename(filename);
      const oldPath = join(root, 'screenshots', oldDir, filename);
      if (!parts.state) {
        // Not a recognized capture filename shape: keep it untouched.
        newPngs[filename] = hash;
        continue;
      }
      const { relPath } = buildScreenshotPath(config, entry, entry.platform || defaultPlatform, parts);
      if (existsSync(oldPath) && resolve(oldPath) !== resolve(join(root, 'screenshots', relPath))) {
        const newPath = join(root, 'screenshots', relPath);
        mkdirSync(dirname(newPath), { recursive: true });
        renameSync(oldPath, newPath);
        moved++;
        lines.push(`MIGRATE_MOVED ${entry.id} ${filename} -> ${relPath}`);
      }
      newPngs[relPath] = hash;
    }
    entryState.pngs = newPngs;
    delete entryState.dir;
  }
  writeJson(join(root, '.screens/state.json'), state);
  lines.push(`MIGRATE_RESULT=OK moved=${moved}`);
  return lines;
}

// ---------------------------------------------------------------------
// marketing: framed store renders (plan's "Marketing" section, stage c)
// ---------------------------------------------------------------------

// Review gate: an unreviewed headline routes its render to `_draft`
// instead of the real marketing output (plan's "Marketing" section).
// Output layout: `_marketing/[_draft/]<platform>/<locale>/<format>/`.
function marketingTargetDir(platform, locale, format, reviewed) {
  const parts = reviewed ? ['_marketing'] : ['_marketing', '_draft'];
  parts.push(platform, locale, format);
  return join(...parts);
}

// Change detection: only re-render when the source PNG hash, the headline
// text, or the review state changed since the last render (a reviewed flip
// moves the file between `_draft` and the real path, so it needs a new
// render even though the pixels are identical).
function marketingNeedsRender(prevRecord, sourceHash, headlineText, reviewed) {
  if (!prevRecord) return true;
  return prevRecord.sourceHash !== sourceHash
    || prevRecord.headlineText !== headlineText
    || prevRecord.reviewed !== reviewed;
}

// Background from the project's token source (plan's "Rendering" note):
// DESIGN.md names the token file, read the first plausible background/
// surface hex value out of it; a project without DESIGN.md, or without a
// resolvable color inside the named file, gets a neutral fallback. Simple
// regex heuristic, deliberately not a CSS/JSON parser: this only ever
// picks a background swatch, never a value the app itself renders.
function resolveMarketingBackground(root) {
  const NEUTRAL = '#f5f5f7';
  const designPath = join(root, 'DESIGN.md');
  if (!existsSync(designPath)) return NEUTRAL;
  const designText = readFileSync(designPath, 'utf8');
  const fileMatch = /\b([\w./-]+\.(?:css|scss|json|ts|js))\b/.exec(designText);
  if (!fileMatch) return NEUTRAL;
  const tokenPath = join(root, fileMatch[1]);
  if (!existsSync(tokenPath)) return NEUTRAL;
  const tokenText = readFileSync(tokenPath, 'utf8');
  const colorMatch = /--(?:[\w-]*)background[\w-]*\s*:\s*(#[0-9a-fA-F]{3,8})/i.exec(tokenText)
    || /"[\w-]*background[\w-]*"\s*:\s*"(#[0-9a-fA-F]{3,8})"/i.exec(tokenText)
    || /(#[0-9a-fA-F]{6}\b)/.exec(tokenText);
  return colorMatch ? colorMatch[1] : NEUTRAL;
}

// Picks the catalog PNG a marketing entry frames: prefers the `filled`
// state, `light` theme, inside `deviceClassPref` (default `desktop`); falls
// back to any `filled` capture, then to whatever PNG exists, so a project
// missing the preferred combination still gets *a* render instead of
// silently skipping the hero.
function findMarketingSourcePng(state, entryId, deviceClassPref = 'desktop') {
  const entryState = state.entries && state.entries[entryId];
  if (!entryState || !entryState.pngs) return null;
  const keys = Object.keys(entryState.pngs);
  const preferred = keys.find((k) => k.includes(`/${deviceClassPref}/`) && k.includes('filled__') && k.includes('light'));
  const anyFilled = keys.find((k) => k.includes('filled__'));
  const relPath = preferred || anyFilled || keys[0];
  return relPath ? { relPath, hash: entryState.pngs[relPath] } : null;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

// Spawns the project-scaffolded `.screens/web/render-marketing.mjs` (the
// project's own Playwright devDependency, see that file's header) with the
// job list on stdin; expects a JSON array of `{id, locale, format, ok,
// reason?}` on stdout. Tests inject a stub renderer instead (plan step 2:
// "Tests for the routing and change detection (renderer injected)").
function defaultMarketingRenderer(root, jobs) {
  const scriptPath = join(root, '.screens/web/render-marketing.mjs');
  if (!existsSync(scriptPath)) {
    return { ok: false, reason: '.screens/web/render-marketing.mjs not scaffolded (run /screens Phase 2 first)' };
  }
  const res = spawnSync('node', [scriptPath], { input: JSON.stringify(jobs), encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (res.status !== 0) {
    return { ok: false, reason: (res.stderr || 'render-marketing.mjs exited non-zero').trim() };
  }
  let rendered;
  try {
    rendered = JSON.parse(res.stdout);
  } catch {
    return { ok: false, reason: 'render-marketing.mjs did not print a JSON result array' };
  }
  return { ok: true, rendered };
}

function cmdMarketing(args, root = process.cwd(), renderer = defaultMarketingRenderer) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  state.marketing = state.marketing || {};
  const entries = (config.marketing && config.marketing.entries) || [];
  const locales = (config.marketing && config.marketing.locales) || ['de'];
  const formats = (config.marketing && config.marketing.formats) || {};
  const defaultPlatform = (config.platforms && config.platforms[0]) || 'web';
  const background = resolveMarketingBackground(root);

  const jobs = [];
  const jobMeta = []; // parallel to jobs: {key, dir, targetPath, reviewed}
  let skipped = 0;
  let notesCount = 0;

  entries.forEach((entry, idx) => {
    const platform = entry.platform || defaultPlatform;
    const source = findMarketingSourcePng(state, entry.source || entry.id);
    for (const locale of locales) {
      const headline = entry.headlines && entry.headlines[locale];
      if (!headline || !headline.text) {
        lines.push(`MARKETING_NOTE ${entry.id} ${locale} no headline configured`);
        notesCount++;
        continue;
      }
      if (!source) {
        lines.push(`MARKETING_NOTE ${entry.id} ${locale} no catalog PNG found for source "${entry.source || entry.id}"`);
        notesCount++;
        continue;
      }
      const format = entry.format || formats[platform] || '1920x1080';
      const reviewed = !!headline.reviewed;
      const dir = marketingTargetDir(platform, locale, format, reviewed);
      const filename = `${pad2(idx + 1)}-${entry.id}.png`;
      const relPath = join(dir, filename);
      const targetPath = join(root, 'screenshots', relPath);
      const key = `${entry.id}__${locale}__${format}`;
      const prevRecord = state.marketing[key];

      if (!marketingNeedsRender(prevRecord, source.hash, headline.text, reviewed)) {
        skipped++;
        lines.push(`MARKETING_SKIP ${entry.id} ${locale} ${format} (unchanged)`);
        continue;
      }

      // A review-state flip changes the target directory; the stale draft
      // file at the old location would otherwise linger as a duplicate.
      if (prevRecord && prevRecord.reviewed !== reviewed && prevRecord.relPath) {
        try {
          rmSync(join(root, 'screenshots', prevRecord.relPath), { force: true });
        } catch {
          // best-effort cleanup only
        }
      }

      jobs.push({
        id: entry.id, locale, format, headline: headline.text, background,
        deviceClass: entry.deviceClass || (platform === 'web' ? 'desktop' : platform),
        sourcePng: join(root, 'screenshots', source.relPath),
        targetPath,
      });
      jobMeta.push({
        key, dir, relPath, targetPath, reviewed,
        sourceHash: source.hash, headlineText: headline.text,
      });
    }
  });

  let rendered = 0;
  let failed = 0;
  if (jobs.length) {
    const result = renderer(root, jobs);
    if (!result.ok) {
      lines.push(`MARKETING_RESULT=FAIL (${result.reason})`);
      return lines;
    }
    for (const r of result.rendered || []) {
      const meta = jobMeta.find((m) => m.key === `${r.id}__${r.locale}__${r.format}`);
      if (!meta) continue;
      if (r.ok) {
        rendered++;
        lines.push(`MARKETING_RENDER ${r.id} ${r.locale} ${r.format} -> ${meta.dir}`);
        state.marketing[meta.key] = {
          sourceHash: meta.sourceHash, headlineText: meta.headlineText,
          reviewed: meta.reviewed, relPath: meta.relPath,
        };
      } else {
        failed++;
        lines.push(`MARKETING_FAIL ${r.id} ${r.locale} ${r.format} (${r.reason || 'render failed'})`);
      }
    }
  }

  writeJson(join(root, '.screens/state.json'), state);

  const draftCount = Object.values(state.marketing).filter((m) => !m.reviewed).length;
  const readyCount = Object.values(state.marketing).filter((m) => m.reviewed).length;
  lines.push(`MARKETING_RESULT=OK rendered=${rendered} skipped=${skipped} failed=${failed} notes=${notesCount} draft=${draftCount} ready=${readyCount}`);
  return lines;
}

// ---------------------------------------------------------------------
// index: filterable screenshots/index.html (plan's "index.html", stage c)
// ---------------------------------------------------------------------

// Reverse of `buildScreenshotPath`'s filename half: promoted catalog
// filenames are `<state>__<role>__<theme>[__<locale>].png` (the viewport
// already moved into the device-class folder, see Output layout).
function parsePromotedFilename(filename) {
  const base = filename.replace(/\.png$/, '');
  const [state, role, theme, locale] = base.split('__');
  return { state, role, theme, locale };
}

// Flattens `state.entries[*].pngs` (full paths relative to `screenshots/`,
// see `entryPngsExist`'s doc comment) into one item per PNG, joined back to
// its manifest entry for `platform`/`area`/`view`. A PNG whose relPath no
// longer parses to 4 path segments (pre-migration legacy layout) is skipped
// rather than guessed at; `migrate-layout` is what fixes that, not `index`.
function buildIndexItems(manifest, state) {
  const items = [];
  for (const entry of manifest.entries || []) {
    const entryState = state.entries && state.entries[entry.id];
    if (!entryState || !entryState.pngs) continue;
    for (const relPath of Object.keys(entryState.pngs)) {
      const segments = relPath.split(sep);
      if (segments.length < 5) continue;
      const [platform, deviceClass, area, view, filename] = segments.slice(-5);
      const parts = parsePromotedFilename(filename);
      if (!parts.state) continue;
      items.push({
        id: entry.id, platform, deviceClass, area, view,
        state: parts.state, role: parts.role, theme: parts.theme, locale: parts.locale || '',
        path: relPath.split(sep).join('/'), // relative to screenshots/, forward slashes for the browser
      });
    }
  }
  return items;
}

// `state.marketing` keys are `${id}__${locale}__${format}`; each stored
// record already carries everything index needs (relPath, headline,
// reviewed) without re-reading config.json.
function buildIndexMarketing(state) {
  const out = [];
  for (const key of Object.keys(state.marketing || {})) {
    const record = state.marketing[key];
    if (!record.relPath) continue;
    const [id, locale, format] = key.split('__');
    out.push({
      id, locale, format, headline: record.headlineText, reviewed: !!record.reviewed,
      path: record.relPath.split(sep).join('/'),
      configPath: '.screens/config.json',
    });
  }
  return out;
}

function cmdIndex(_args, root = process.cwd()) {
  const lines = [];
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  const templatePath = join(dirname(fileURLToPath(import.meta.url)), '..', 'templates', 'index.html');
  if (!existsSync(templatePath)) {
    lines.push('INDEX_RESULT=FAIL (templates/index.html not found)');
    return lines;
  }

  const items = buildIndexItems(manifest, state);
  const marketing = buildIndexMarketing(state);
  const data = { items, marketing, last_run: state.last_run || {} };

  const template = readFileSync(templatePath, 'utf8');
  const html = template.replace('__SCREENS_DATA__', () => JSON.stringify(data));

  const outPath = join(root, 'screenshots', 'index.html');
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, html);

  lines.push(`INDEX_ITEMS=${items.length}`);
  lines.push(`INDEX_MARKETING=${marketing.length}`);
  lines.push(`INDEX_RESULT=OK path=screenshots/index.html`);
  return lines;
}

// ---------------------------------------------------------------------
// trust: repo-supplied command string re-confirmation (Trust boundary)
// ---------------------------------------------------------------------

function computeCommandHash(config) {
  const values = [];
  (function walk(obj) {
    if (!obj || typeof obj !== 'object') return;
    for (const [k, v] of Object.entries(obj)) {
      if (typeof v === 'string' && /command$/i.test(k)) values.push(v);
      else if (typeof v === 'object') walk(v);
    }
  })(config);
  values.sort();
  return createHash('sha256').update(values.join('\n')).digest('hex');
}

function cmdTrust(args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const state = readJson(join(root, '.screens/state.json'), {});
  const hash = computeCommandHash(config);
  if (args.includes('--confirm')) {
    state.command_hash = hash;
    writeJson(join(root, '.screens/state.json'), state);
    lines.push('TRUST_RESULT=OK (confirmed)');
    return lines;
  }
  if (!state.command_hash || state.command_hash !== hash) {
    lines.push(`TRUST_RESULT=NEEDS_CONFIRM (hash=${hash})`);
  } else {
    lines.push('TRUST_RESULT=OK');
  }
  return lines;
}

// ---------------------------------------------------------------------
// affected: used by /delegate Phase 3.5/5 (plan step 11, later stage)
// ---------------------------------------------------------------------

function affectedIds(manifest, config, files) {
  const globalSources = config.global_sources || [];
  const ids = new Set();
  for (const entry of manifest.entries || []) {
    const sources = entry.sources || [];
    for (const f of files) {
      if (sources.some((g) => matchesGlob(f, g)) || globalSources.some((g) => matchesGlob(f, g))) {
        ids.add(entry.id);
      }
    }
  }
  return [...ids].sort();
}

function cmdAffected(args, root = process.cwd()) {
  const lines = [];
  const filesIdx = args.indexOf('--files');
  const files = filesIdx >= 0 ? args.slice(filesIdx + 1) : [];
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const config = readJson(join(root, '.screens/config.json'), {});
  const ids = affectedIds(manifest, config, files);
  for (const id of ids) lines.push(`AFFECTED_ID ${id}`);
  lines.push(`AFFECTED_RESULT=OK count=${ids.length}`);
  return lines;
}

// ---------------------------------------------------------------------
// CLI entrypoint
// ---------------------------------------------------------------------

function main(argv) {
  const [cmd, ...rest] = argv;
  const handlers = {
    plan: cmdPlan,
    up: cmdUp,
    down: cmdDown,
    promote: cmdPromote,
    'migrate-layout': cmdMigrateLayout,
    marketing: cmdMarketing,
    index: cmdIndex,
    trust: cmdTrust,
    affected: cmdAffected,
  };
  const handler = handlers[cmd];
  if (!handler) {
    console.log(`SCREENS_RESULT=FAIL (unknown subcommand: ${cmd || '(none)'})`);
    return;
  }
  for (const line of handler(rest)) console.log(line);
}

const isMain = process.argv[1] && (() => {
  try {
    return resolve(process.argv[1]) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
})();
if (isMain) main(process.argv.slice(2));

export {
  matchesGlob,
  listRepoFiles,
  resolveGlobs,
  computeFingerprint,
  entryPngsExist,
  listDirFiles,
  planEntries,
  cmdPlan,
  checkLock,
  repoHash,
  simulatorNameForDevice,
  parseDfAvailableGb,
  checkDiskGuard,
  findNewestIosRuntimeId,
  findSimulatorUdidByName,
  statusBarOverrideArgs,
  appearanceArgs,
  iosDeviceSetup,
  macosDeviceSetup,
  androidAvdName,
  androidEmulatorPort,
  resolveAndroidSdkRoot,
  androidToolPaths,
  androidToolsPreflight,
  probeAndroidTools,
  avdExists,
  findInstalledSystemImages,
  androidAvdCreateShellCmd,
  androidDemoModeArgs,
  androidThemeArgs,
  waitForAndroidBoot,
  androidDeviceSetup,
  deviceSetupHook,
  laravelDbGuard,
  bunDbGuard,
  composePhpIniScanDir,
  phpFixedClockEnv,
  laravelPerfEnv,
  playwrightWorkers,
  computeSeedFingerprint,
  cmdUp,
  cmdDown,
  commandOnPath,
  readPngDimensions,
  defaultCompareRunner,
  parseAeCount,
  promoteFile,
  deviceClassFor,
  parseCaptureFilename,
  buildScreenshotPath,
  moveRemovedEntries,
  cmdPromote,
  cmdMigrateLayout,
  marketingTargetDir,
  marketingNeedsRender,
  resolveMarketingBackground,
  findMarketingSourcePng,
  defaultMarketingRenderer,
  cmdMarketing,
  parsePromotedFilename,
  buildIndexItems,
  buildIndexMarketing,
  cmdIndex,
  computeCommandHash,
  cmdTrust,
  affectedIds,
  cmdAffected,
  readJson,
  writeJson,
};
