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
// Per-project files this CLI reads/writes (config, manifest, state, secrets,
// drivers) all live under `.screens/` in the TARGET project (never under
// `.claude/`, see repo CLAUDE.md "Per-project files live in .screens/, not
// .claude/"). The PNG catalog itself does NOT: it lives under a central
// `~/Developer/screens/<project-slug>/` folder (or `config.output_dir` when
// set), resolved once by `resolveScreensOutputRoot` below and used by every
// reader/writer of catalog PNGs.

import {
  readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync,
  rmSync, renameSync, chmodSync, copyFileSync, statSync, appendFileSync,
} from 'node:fs';
import { join, dirname, basename, relative, resolve, sep } from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
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

// `${PROJECT_ROOT}` placeholder (stage (f) follow-up 1): a manifest/config
// string value may reference the project root symbolically instead of an
// absolute path baked in at discovery time (e.g. a native fixture path in
// `launch_args`, config-schema.md). Recurses through arrays/objects so a
// whole config/manifest subtree (env maps, nested launch_args/steps) expands
// in one call; only string leaves are touched, and an unknown `${X}`
// placeholder is left untouched. Single Node implementation; the non-Node
// driver templates (capture.spec.ts, ScreensCatalogTests.swift,
// generate-maestro-flows.mjs) carry their own small equivalent since they
// run outside this file.
function expandProjectRoot(value, root) {
  if (typeof value === 'string') return value.replaceAll('${PROJECT_ROOT}', resolve(root));
  if (Array.isArray(value)) return value.map((v) => expandProjectRoot(v, root));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = expandProjectRoot(v, root);
    return out;
  }
  return value;
}

// ---------------------------------------------------------------------
// Output root resolution (central screenshot folder, `~/Developer/screens/`)
// ---------------------------------------------------------------------

// `~` / `~/...` expansion for `config.output_dir`; a bare relative or
// already-absolute path passes through untouched.
function expandHome(p) {
  if (!p) return p;
  if (p === '~') return os.homedir();
  if (p.startsWith('~/')) return join(os.homedir(), p.slice(2));
  return p;
}

// Every directory literally named `.screens` under `dir` (excluding
// `.git`/`node_modules`/`.claude`), used by `deriveProjectSlug` to decide
// whether a nested `.screens` root (e.g. a multi-platform project's
// `ios/.screens`) needs its subpath appended to the slug -- only when the
// SAME project family has more than one `.screens` root, so a
// single-platform project (`topf-secret/ios`) still gets the short
// family-name slug. `.claude` is excluded because `.claude/worktrees/*`
// holds full isolated checkouts of the SAME repo (verified live against
// the topf-secret pilot: three worktree copies each carry their own
// `ios/.screens`), which are not separate platform subprojects.
function findScreensRoots(dir) {
  const out = [];
  (function walk(d) {
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name === '.git' || entry.name === 'node_modules' || entry.name === '.claude') continue;
      const full = join(d, entry.name);
      if (entry.name === '.screens') {
        out.push(full);
        continue;
      }
      walk(full);
    }
  })(dir);
  return out;
}

// The project "family" directory a `.screens` root belongs to: this
// user's own convention (repo CLAUDE.md, every pilot) is
// `~/Developer/apps/<name>/...`, and platform subprojects under one
// `<name>` are routinely independent git repos (verified live: `zeit/app`
// and `zeit/macos` are two separate repos, so a git-top-level-based slug
// would split one product's catalog into two) -- the shared slug therefore
// comes from the fixed directory convention, not from git. A `root`
// outside `~/Developer/apps/` has no family to share a slug with.
function projectFamilyDir(root) {
  const devApps = join(os.homedir(), 'Developer', 'apps');
  const rel = relative(devApps, resolve(root));
  if (!rel || rel.startsWith('..') || resolve(rel) === rel) return null;
  const name = rel.split(sep)[0];
  return { dir: join(devApps, name), name };
}

// Project slug for the central `~/Developer/screens/<slug>/` folder (user
// decision, "Output root resolution"): the family directory's own name,
// with the `.screens` root's own subpath appended ONLY when the family has
// more than one `.screens` root (several platform subprojects) --
// `zeit/app`, `topf-secret/ios`, `layer` and `events` all resolve to their
// bare family name since each family has exactly one `.screens` root today.
// A `root` outside `~/Developer/apps/` (test fixtures, a project living
// elsewhere) falls back to its own directory name.
function deriveProjectSlug(root) {
  const absRoot = resolve(root);
  const family = projectFamilyDir(absRoot);
  if (!family) return basename(absRoot);
  if (resolve(family.dir) === absRoot) return family.name;
  const otherRoots = findScreensRoots(family.dir).filter((r) => resolve(dirname(r)) !== absRoot);
  if (!otherRoots.length) return family.name;
  const rel = relative(family.dir, absRoot).split(sep).join('-');
  return `${family.name}-${rel}`;
}

// The one helper every writer/reader of catalog PNGs goes through (plan
// "Output root resolution"): `config.output_dir` (supporting `~` and
// `${PROJECT_ROOT}`) when set, else `~/Developer/screens/<slug>`. Config,
// manifest, drivers, secrets and `state.json` all stay under the project's
// own `.screens/`; only the PNG catalog itself moves.
function resolveScreensOutputRoot(root, config) {
  const slug = config.project || deriveProjectSlug(root);
  if (config.output_dir) {
    const expanded = expandProjectRoot(expandHome(config.output_dir), root);
    return { outputRoot: resolve(expanded), slug };
  }
  return { outputRoot: join(os.homedir(), 'Developer', 'screens', slug), slug };
}

// Persists the resolved slug into `config.project` on first run (plan:
// "stable"), so a later repo move/rename can't silently change where an
// existing catalog is found. Mutates the passed-in `config` object too, so
// the caller's own subsequent reads in the same process see it immediately.
function ensureProjectConfigured(root, config) {
  const resolved = resolveScreensOutputRoot(root, config);
  if (!config.project && resolved.slug) {
    config.project = resolved.slug;
    writeJson(join(root, '.screens/config.json'), config);
  }
  return resolved;
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

// `pngs` keys are full paths relative to the resolved output root
// (device-class layout, Output layout section) since the migrate-layout
// pass; a legacy entry that still carries `dir` is resolved through it so
// `plan` stays correct before `migrate-layout` has run.
function entryPngsExist(outputRoot, entryState) {
  if (!entryState || !entryState.pngs) return false;
  return Object.keys(entryState.pngs).some((f) => {
    const rel = entryState.dir ? join(entryState.dir, f) : f;
    return existsSync(join(outputRoot, rel));
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
  const { outputRoot } = ensureProjectConfigured(root, config);
  const globalSources = config.global_sources || [];
  const results = [];
  for (const entry of manifest.entries || []) {
    const fingerprint = computeFingerprint(root, entry.sources || [], globalSources);
    const prev = state.entries && state.entries[entry.id];
    let status;
    if (!prev) status = 'new';
    else if (fingerprint !== prev.fingerprint) status = 'stale';
    else if (full) status = 'stale';
    else if (!entryPngsExist(outputRoot, prev)) status = 'missing_png';
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
// macOS attachment export (xcresulttool). The macOS UI test runner is
// sandboxed and cannot write a PNG into the project directory
// (NSCocoaErrorDomain 513 / EPERM, reproduced live against the layer
// pilot on 2026-09-24), so `ScreensCatalogTests.swift`'s macOS `capture`
// never attempts the direct write it uses for iOS: every macOS screenshot
// is delivered as an `XCTAttachment`
// inside the `.xcresult` bundle `-resultBundlePath` wrote instead
// (`screens/references/platform-apple.md` "Invocation"). This step pulls
// those PNGs back out via `xcrun xcresulttool export attachments` and
// renames them into `.screens/.incoming/macos/` under the filename
// `promote` already expects, so `promote` stays generic over how a
// driver got a PNG there.
// ---------------------------------------------------------------------

// Pure command composition (plan step 1 testability: "Tests (node, runner
// injected): export command composition"); the actual spawn happens in
// `cmdMacosExport` via the injected runner. `--filter "*.png"` skips the
// UI-hierarchy/debug-description/video attachments XCUITest itself
// records on every run (verified live: 27 attachments for 2 screenshots
// without the filter).
function xcresultExportAttachmentsArgs(resultBundlePath, outputPath) {
  return ['xcresulttool', 'export', 'attachments', '--path', resultBundlePath, '--output-path', outputPath, '--filter', '*.png'];
}

// xcresulttool's own export manifest.json never names an exported file
// exactly what `ScreensCatalogTests.swift`'s `attachScreenshot` set as the
// `XCTAttachment.name`: it appends a `_<index>_<UUID>` disambiguation
// suffix before the extension unconditionally (verified live against
// Xcode 27: `content-view-with-model__filled__guest__mac__dark.png` came
// back as `..._0_96B887EF-3941-4AF2-B98F-5ECBAEE2068E.png`), so recovering
// the name `promote` expects means stripping exactly that suffix, not
// trusting `suggestedHumanReadableName` verbatim.
const XCRESULT_SUFFIX_RE = /_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(\.[^.]+)$/;

function stripXcresultSuffix(suggestedName) {
  return suggestedName.replace(XCRESULT_SUFFIX_RE, '$1');
}

// Parses xcresulttool's `export attachments` manifest.json (top-level
// array of `{testIdentifier, attachments: [{exportedFileName,
// suggestedHumanReadableName, ...}]}`, verified against a real export on
// this Xcode 27 install, `xcrun xcresulttool export attachments --schema`)
// into `{exportedFileName -> incomingFilename}` pairs for every `.png`
// attachment, so `cmdMacosExport` never has to re-derive xcresulttool's
// naming convention itself.
function mapXcresultExportToIncoming(manifestJson) {
  const out = {};
  for (const testEntry of manifestJson || []) {
    for (const attachment of testEntry.attachments || []) {
      const exportedFileName = attachment.exportedFileName;
      const suggestedName = attachment.suggestedHumanReadableName;
      if (!exportedFileName || !suggestedName || !suggestedName.endsWith('.png')) continue;
      out[exportedFileName] = stripXcresultSuffix(suggestedName);
    }
  }
  return out;
}

// Runs the export, reads its manifest.json, and moves every mapped PNG
// into `.screens/.incoming/macos/` (platform-apple.md "Invocation" runs
// this once per themed xcodebuild pass, right after that pass's
// `-resultBundlePath` bundle is written and before the next theme
// overwrites it). No result bundle yet (a driver failure before any test
// ran) is a SKIP, not a FAIL: `down` still needs to run.
function cmdMacosExport(args, root = process.cwd(), runner = defaultRunner) {
  const lines = [];
  const resultBundlePath = argValue(args, '--result-bundle') || join(root, '.screens/.build/macos/Result.xcresult');
  if (!existsSync(resultBundlePath)) {
    lines.push(`MACOS_EXPORT_RESULT=SKIP (no result bundle at ${resultBundlePath})`);
    return lines;
  }

  const incomingDir = join(root, '.screens/.incoming/macos');
  const exportDir = join(root, '.screens/.build/macos/_export');
  rmSync(exportDir, { recursive: true, force: true });
  const exportRes = runner('xcrun', xcresultExportAttachmentsArgs(resultBundlePath, exportDir), {});
  if (exportRes.status !== 0) {
    lines.push(`MACOS_EXPORT_RESULT=FAIL (xcresulttool export attachments exited ${exportRes.status})`);
    return lines;
  }

  const manifestJson = readJson(join(exportDir, 'manifest.json'), null);
  const mapping = manifestJson ? mapXcresultExportToIncoming(manifestJson) : {};
  mkdirSync(incomingDir, { recursive: true });
  let moved = 0;
  for (const [exportedFileName, incomingFilename] of Object.entries(mapping)) {
    const src = join(exportDir, exportedFileName);
    if (!existsSync(src)) continue;
    renameSync(src, join(incomingDir, incomingFilename));
    moved++;
  }
  lines.push(`MACOS_EXPORT_RESULT=OK moved=${moved}`);
  return lines;
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
    avdmanager: existsSync(tools.avdmanager) || commandOnPath('avdmanager'),
  };
}

// Resolves the actual avdmanager path to invoke: the SDK-root-relative
// location first (matches `androidToolPaths`' contract when a full SDK
// including cmdline-tools is installed there), falling back to a bare
// PATH lookup when a package manager installed avdmanager outside the
// SDK root -- verified live: `brew install android-commandlinetools`
// puts avdmanager/sdkmanager under its own keg
// (/opt/homebrew/share/android-commandlinetools/...), while adb/emulator/
// system-images stay under ~/Library/Android/sdk. A bare command name
// resolves via PATH the same way `commandOnPath` checks it (execvp
// semantics), so `runner`/`spawnSync` need no extra plumbing here.
function resolveAvdmanagerPath(sdkRoot, exists = existsSync, onPath = commandOnPath) {
  const sdkPath = join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager');
  if (exists(sdkPath)) return sdkPath;
  if (onPath('avdmanager')) return 'avdmanager';
  return sdkPath;
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

// Explicit-component intent (plan step 9, live 2026-09-24 against the events
// pilot): Maestro's `openLink` resolves an IMPLICIT VIEW intent, which
// Android routes to Chrome because the app's own App Link intent-filter only
// verifies the production host (`AndroidManifest.xml`), never the isolated
// backend host the driver points `server.url` at
// (`am start -a VIEW -d http://10.0.2.2:<port>/...` -> "Unable to resolve
// Intent", reproduced live). An EXPLICIT component intent (`-n
// <appId>/.MainActivity`) skips intent-filter resolution entirely and is
// delivered straight to the running app's `onNewIntent`, where Capacitor's
// App plugin fires `appUrlOpen` with the intent's data -- the app's own JS
// then narrows that event by hostname (`androidDeepLinkUrl` below) before
// navigating. The activity is always `.MainActivity` (Capacitor's own
// generated activity name, never renamed per-project).
function androidExplicitIntentArgs(serial, appId, url) {
  return [
    '-s', serial, 'shell', 'am', 'start',
    '-n', `${appId}/.MainActivity`,
    '-a', 'android.intent.action.VIEW',
    '-d', url,
  ];
}

// The intent's `-d` URL must carry the app's own verified deep-link host
// (the app's JS narrows the `appUrlOpen` event by exact hostname, see
// `androidExplicitIntentArgs` above and `platform-maestro.md` "Explicit-
// intent navigation"), never the isolated backend host the webview is
// actually pointed at -- the app then loads only the URL's path against its
// already-isolated `server.url`. `config.android.deep_link_host` declares
// that host per project (the App Link intent-filter's own `android:host` in
// `AndroidManifest.xml`); there is no safe generic default.
function androidDeepLinkUrl(deepLinkHost, reach) {
  return `https://${deepLinkHost}${reach}`;
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
function androidDeviceSetup(root, config, runner = defaultRunner, probe = probeAndroidTools, resolveAvdmanager = resolveAvdmanagerPath) {
  const diskSkip = diskGuardSkip(root, runner);
  if (diskSkip) return diskSkip;

  const androidConfig = config.android || {};
  const sdkRoot = resolveAndroidSdkRoot();
  const tools = androidToolPaths(sdkRoot);
  const preflight = androidToolsPreflight(probe(sdkRoot));
  if (!preflight.ok) return { ok: true, skip: true, reason: preflight.reason };

  // avdmanager may live outside sdkRoot (see `resolveAvdmanagerPath`); the
  // invocation below always uses the resolved path, never `tools.avdmanager`
  // directly, so a brew-only cmdline-tools install (adb/emulator under
  // ~/Library/Android/sdk, avdmanager under a separate keg) still works.
  tools.avdmanager = resolveAvdmanager(sdkRoot);

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

// Laravel isolation env default (live STOP: `config/session.php`'s
// `'secure' => env('SESSION_SECURE_COOKIE', true)` drops the session
// cookie after login on the isolated http backend, since a `secure`
// cookie never reaches the browser over plain http). Applied before
// `platformConfig.env` in the merge below so a project's own
// `SESSION_SECURE_COOKIE` in `config.web.env` still wins.
//
// `SESSION_EXPIRE_ON_CLOSE=true` (live STOP: the server-side fixed clock,
// `fixed-clock.php`'s `Carbon::setTestNow($fixedNow)`, freezes every
// `now()` the running `php artisan serve` process computes, including
// `config/session.php`'s cookie `Expires`/`Max-Age`, which Laravel derives
// as `now()->addMinutes($lifetime)`. Once real wall-clock time passes
// `config.web.fixed_now`, that computed expiry is already in the past, so
// the browser discards the Set-Cookie header on arrival and every login
// silently fails to persist past the very next request -- reproduced
// against the events pilot: `fixed_now` 2026-05-12, real date 2026-09-24,
// every `Set-Cookie: <session>=...; expires=Tue, 12 May 2026 ...` request
// immediately expired). `session.expire_on_close` makes Laravel omit
// `Expires`/`Max-Age` entirely (a browser-session cookie instead), so the
// frozen clock can no longer produce an already-expired header; the
// server-side "has this session expired" check still reads the same
// frozen `now()`, so session GC/lifetime enforcement stays internally
// consistent with the rest of the isolated run.
function laravelSessionEnv(platformConfig) {
  if (platformConfig.framework !== 'laravel') return {};
  return { SESSION_SECURE_COOKIE: 'false', SESSION_EXPIRE_ON_CLOSE: 'true' };
}

// DEMO_USER_PASSWORD plus any `secret_env_aliases` (config field, names
// only, see `secretConfigGuard`): sets each listed name to the same demo
// password, for a project whose own env variable for the demo password is
// not called `DEMO_USER_PASSWORD` -- an alternative to editing project
// source to add that name. Never printed (see `ensureSecretsFile`).
function demoPasswordEnv(platformConfig, demoSecrets) {
  if (!demoSecrets.demoPassword) return {};
  const env = { DEMO_USER_PASSWORD: demoSecrets.demoPassword };
  for (const alias of platformConfig.secret_env_aliases || []) env[alias] = demoSecrets.demoPassword;
  return env;
}

// PID file location (fix: moved from `.screens/<platform>/pid` to
// `.screens/.run/<platform>.pid` so every platform's runtime pid lives
// under one gitignored directory instead of one bespoke subdirectory
// each; shared by `cmdUp`'s writer and `cmdDown`'s reader/cleanup).
function pidFilePath(root, platform) {
  return join(root, '.screens/.run', `${platform}.pid`);
}

// Capacitor-dependent web backend (live 2026-09-24 STOP, "Explicit-intent
// navigation" in platform-maestro.md): a Laravel `route()`/`asset()` call
// builds an ABSOLUTE url from `APP_URL`, and a client-side redirect using it
// (e.g. an unauthenticated Livewire redirect to the login route) takes the
// Android webview OFF `server.url`'s origin. Capacitor's plugin bridge is
// injected per-origin, so leaving it drops EVERY plugin to "not implemented
// on android", not just navigation (live: 9 hits across App/SystemBars/
// PushNotifications/Keyboard/Preferences after the very first such
// redirect, `APP_URL` still resolving to the project's own dev host).
// `config.android.depends_on === 'web'` is the same declared relationship
// `androidDeviceSetup`'s own doc already describes; `APP_URL` is set to the
// emulator-reachable host so every redirect stays on the origin the bridge
// was injected into. Never overrides an explicit `config.web.env.APP_URL`
// (a project's own choice always wins).
function androidAppUrlEnv(config) {
  const androidConfig = config.android;
  if (!androidConfig || androidConfig.depends_on !== 'web') return {};
  if (config.web && config.web.env && config.web.env.APP_URL) return {};
  const webConfig = config.web || {};
  const appUrl = androidConfig.base_url || `http://10.0.2.2:${webConfig.port || ''}`;
  return { APP_URL: appUrl };
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

// ---------------------------------------------------------------------
// Demo password (per-machine secret, security fix: no demo password lives
// in any repo, config.json, or generated driver file). `.screens/
// secrets.local.json` is created once per machine by the seed step below,
// reused on every later run, mode 0600, gitignored. Rotating it means
// deleting it together with the isolated DB.
// ---------------------------------------------------------------------

const DEMO_PASSWORD_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function generateDemoPassword() {
  const bytes = randomBytes(24);
  let out = '';
  for (let i = 0; i < 24; i++) out += DEMO_PASSWORD_ALPHABET[bytes[i] % DEMO_PASSWORD_ALPHABET.length];
  return out;
}

// Adds `entry` to the project's `.gitignore` unless `git check-ignore`
// already covers it (same "check before appending" pattern as `audit/bin/
// cache-write.sh`/`patterns-store.sh`, repo CLAUDE.md Gotchas): a broader
// existing rule is left alone, and the append never happens twice.
function ensureGitignoreEntry(root, entry, runner = defaultRunner) {
  const checkRes = runner('git', ['-C', root, 'check-ignore', '-q', entry], {});
  if (checkRes.status === 0) return;
  const gitignorePath = join(root, '.gitignore');
  let content = '';
  try {
    content = readFileSync(gitignorePath, 'utf8');
  } catch {
    // no .gitignore yet: starts empty
  }
  if (content.split('\n').some((line) => line.trim() === entry)) return;
  const leadingNewline = content && !content.endsWith('\n') ? '\n' : '';
  writeFileSync(gitignorePath, content + leadingNewline + entry + '\n');
}

// Per-machine demo password (a DB seeded with an unknown password is
// useless, so a missing file forces a reseed this run). Missing file:
// generate, write 0600, gitignore it, `forceReseed: true`. Existing file:
// reused verbatim, never regenerated while it exists. Never prints the
// password itself, only CREATED/REUSED.
function ensureSecretsFile(root, runner = defaultRunner) {
  const path = join(root, '.screens/secrets.local.json');
  if (existsSync(path)) {
    const secrets = readJson(path, {});
    console.log('SECRET=REUSED');
    return {
      demoPassword: secrets.demo_password,
      demoPasswordEmpty: secrets.demo_password_empty,
      forceReseed: false,
    };
  }
  const password = generateDemoPassword();
  writeJson(path, { demo_password: password });
  chmodSync(path, 0o600);
  ensureGitignoreEntry(root, '/.screens/secrets.local.json', runner);
  console.log('SECRET=CREATED');
  return { demoPassword: password, demoPasswordEmpty: undefined, forceReseed: true };
}

// Refuses `up` (FAIL) when a secret still lives in the committed config
// instead of `.screens/secrets.local.json`: a literal `demo_password` key,
// or any `web.env` key that looks like a secret (PASSWORD/SECRET/TOKEN,
// case-insensitive).
function secretConfigGuard(config) {
  if (config.demo_password) {
    return { ok: false, reason: 'config.json has a demo_password key; move it to .screens/secrets.local.json' };
  }
  const env = (config.web && config.web.env) || {};
  for (const key of Object.keys(env)) {
    if (/PASSWORD|SECRET|TOKEN/i.test(key)) {
      return { ok: false, reason: `config.web.env.${key} looks like a secret; move it to .screens/secrets.local.json` };
    }
  }
  return { ok: true };
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

  // Marketing 2x source captures (`marketing.source_scale`, config-schema.md)
  // land in `.screens/.marketing-src/` via the project's own `capture.spec.ts`
  // (outside screens.mjs's control), so this is the only point in the
  // lifecycle where the directory's existence is known ahead of the write:
  // same "gitignore before the generated file exists" pattern as the secrets
  // file and `.run/` above.
  if (platform === 'web' && config.marketing && config.marketing.entries && config.marketing.entries.length) {
    ensureGitignoreEntry(root, '/.screens/.marketing-src/', runner);
  }

  const secretGuard = secretConfigGuard(config);
  if (!secretGuard.ok) {
    lines.push(`UP_RESULT=FAIL (${secretGuard.reason})`);
    return lines;
  }

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
    // Consumed by the xcodebuild invocation as TEST_RUNNER_SCREENS_PROJECT_ROOT
    // (platform-apple.md "Invocation"), so ScreensCatalogTests.swift can
    // expand `${PROJECT_ROOT}` in launch_args/extra_args/steps itself.
    lines.push(`PROJECT_ROOT=${resolve(root)}`);
  }

  // `${PROJECT_ROOT}` expansion applies to the whole platform block up
  // front: `start_command`, `seed_command`, `env`, `isolated_db` and any
  // native-only field (`launch_args`/`extra_args`/`steps` live in the
  // manifest, expanded by the driver templates themselves) all reach a
  // driver from here.
  const platformConfig = expandProjectRoot(config[platform] || {}, root);

  // Seed step, before the seed command below: a DB seeded with an unknown
  // password is useless, so a freshly created secrets file forces a
  // reseed this run (`demoSecrets.forceReseed`, folded into `full` below).
  let demoSecrets = { demoPassword: undefined, demoPasswordEmpty: undefined, forceReseed: false };
  if (platformConfig.seed_command) {
    demoSecrets = ensureSecretsFile(root, runner);
  }

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
  const sessionEnv = platform === 'web' ? laravelSessionEnv(platformConfig) : {};
  const perfEnv = platform === 'web' ? laravelPerfEnv(platformConfig) : {};
  const appUrlEnv = platform === 'web' ? androidAppUrlEnv(config) : {};
  // DEMO_USER_PASSWORD (+ secret_env_aliases): reaches both the seed
  // command and the serve process below, same as every other env source
  // here.
  const demoEnv = demoPasswordEnv(platformConfig, demoSecrets);
  // `sessionEnv` sits before `platformConfig.env` so a project's own
  // `SESSION_SECURE_COOKIE` still wins (see `laravelSessionEnv`).
  const runEnv = { ...sessionEnv, ...(platformConfig.env || {}), ...clockEnv, ...perfEnv, ...appUrlEnv, ...demoEnv };

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
    // Migrate: an old-layout pidfile from a previous screens.mjs never
    // gets read again once the new one is written, so it is removed here
    // rather than left stale on disk.
    rmSync(join(root, '.screens', platform, 'pid'), { force: true });
    const pidFile = pidFilePath(root, platform);
    mkdirSync(dirname(pidFile), { recursive: true });
    writeFileSync(pidFile, String(child.pid));
    ensureGitignoreEntry(root, '/.screens/.run/', runner);
    lines.push(`PID=${child.pid}`);
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

  // Seed before the health check: a freshly created isolated DB has no
  // migrations yet, so a health_url that renders a DB-backed page (e.g. a
  // Laravel landing route) 500s until migrate/seed has run. Checking health
  // first made `up` time out on every first run against such a route
  // (verified live against the events pilot's isolated pgsql DB, which had
  // no `events` table pre-seed).
  if (platformConfig.seed_command) {
    const full = args.includes('--full') || args.includes('--reseed') || demoSecrets.forceReseed;
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

  if (platformConfig.health_url) {
    if (!waitForHealth(platformConfig.health_url, 90)) {
      lines.push('UP_RESULT=FAIL (service never healthy within 90s)');
      return lines;
    }
    lines.push('HEALTH=OK');
  }

  lines.push(`PLAYWRIGHT_WORKERS=${playwrightWorkers(os.cpus().length)}`);
  lines.push('UP_RESULT=OK');
  return lines;
}

// Process-tree fallback (plan step 9, live 2026-09-24 STOP: a `php artisan
// serve --port=<port>` worker child, spawned via `PHP_CLI_SERVER_WORKERS`
// (`laravelPerfEnv`), survived the pidfile's own `-pid` process-group kill
// below on a real run against the events pilot). Kills any process still
// listening on the recorded port, but ONLY when that process's own cwd
// resolves under `root` -- never an unrelated listener on the same port
// from another tool, checked via `lsof -a -p <pid> -d cwd` before the kill,
// same "verify ownership before touching" reasoning as the lock/PID checks
// above.
function killPortListeners(root, port, runner = defaultRunner) {
  if (!port) return;
  const lsofRes = runner('lsof', ['-ti', `tcp:${port}`], {});
  const pids = (lsofRes.stdout || '').trim().split('\n').filter(Boolean);
  for (const pidStr of pids) {
    const pid = parseInt(pidStr, 10);
    if (!pid) continue;
    const cwdRes = runner('lsof', ['-a', '-p', String(pid), '-d', 'cwd', '-Fn'], {});
    const cwdLine = (cwdRes.stdout || '').split('\n').find((l) => l.startsWith('n'));
    const procCwd = cwdLine ? resolve(cwdLine.slice(1)) : '';
    const rootAbs = resolve(root);
    const underRoot = procCwd && (procCwd === rootAbs || procCwd.startsWith(rootAbs + sep));
    if (!underRoot) continue;
    try {
      process.kill(pid, 'SIGTERM');
    } catch {
      // already gone
    }
  }
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
    const pidFile = pidFilePath(root, platform);
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
    // Process-tree fallback (`killPortListeners` above): only a platform
    // config that declares `port` (web) is checked -- android's `adb emu
    // kill` above is the emulator's own graceful shutdown, no port to fall
    // back on.
    const platformPort = config[platform] && config[platform].port;
    if (platformPort) killPortListeners(root, platformPort, runner);
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
// android-navigate: sends the per-entry explicit intent
// (`androidExplicitIntentArgs`/`androidDeepLinkUrl` above) ahead of that
// entry's Maestro flow (platform-maestro.md "Explicit-intent navigation"),
// one call per manifest entry from the driver's invocation loop -- the
// Maestro flow itself only brings the app to the foreground (`launchApp`)
// and waits/screenshots, it never navigates.
// ---------------------------------------------------------------------

function cmdAndroidNavigate(args, root = process.cwd(), runner = defaultRunner) {
  const lines = [];
  const entryId = argValue(args, '--entry');
  const serial = argValue(args, '--serial');
  if (!entryId || !serial) {
    lines.push('ANDROID_NAVIGATE_RESULT=FAIL (--entry and --serial required)');
    return lines;
  }
  const config = readJson(join(root, '.screens/config.json'), {});
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const entry = (manifest.entries || []).find((e) => e.id === entryId);
  if (!entry) {
    lines.push(`ANDROID_NAVIGATE_RESULT=FAIL (unknown entry ${entryId})`);
    return lines;
  }
  if (!entry.reach) {
    lines.push(`ANDROID_NAVIGATE_RESULT=SKIP (entry ${entryId} has no reach URL)`);
    return lines;
  }
  const androidConfig = config.android || {};
  const appId = androidConfig.app_id;
  const deepLinkHost = androidConfig.deep_link_host;
  if (!appId || !deepLinkHost) {
    lines.push('ANDROID_NAVIGATE_RESULT=FAIL (config.android.app_id and deep_link_host required)');
    return lines;
  }
  const url = androidDeepLinkUrl(deepLinkHost, entry.reach);
  const sdkRoot = resolveAndroidSdkRoot();
  const adb = androidToolPaths(sdkRoot).adb;
  const res = runner(adb, androidExplicitIntentArgs(serial, appId, url), {});
  if (res.status !== 0) {
    lines.push(`ANDROID_NAVIGATE_RESULT=FAIL (am start exited ${res.status})`);
    return lines;
  }
  lines.push(`ANDROID_NAVIGATE_RESULT=OK url=${url}`);
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
// `historyPath` (Change history spec item 1), when given, is where the
// PNG about to be overwritten is moved first -- gated on the exact same
// condition that already distinguishes a real overwrite (`changed`/`drift`)
// from a brand-new promotion (`new`, no `prevHash`) or a no-write verdict
// (`unchanged`/`tolerated`, both return above before this point): a
// `prevHash` was recorded AND a file exists at `targetPath` right now.
function promoteFile(incomingPath, targetPath, prevHash, opts = {}) {
  const {
    diffTolerance = 0.0001,
    hasCompare = commandOnPath('compare'),
    compareRunner = defaultCompareRunner,
    historyPath = null,
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
  let historized = false;
  if (prevHash && existsSync(targetPath) && historyPath) {
    mkdirSync(dirname(historyPath), { recursive: true });
    renameSync(targetPath, historyPath);
    historized = true;
  }
  mkdirSync(dirname(targetPath), { recursive: true });
  writeFileSync(targetPath, buf);
  return { changed: true, hash, tolerated: false, historized };
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

// `onMove(id, rel)` (Change history spec item 3, run log) is an optional
// per-file hook so `cmdPromote` can collect `{id, path}` detail for
// `runs.jsonl`'s `removed` array without this function's own return shape
// (plain array of moved ids, asserted by an existing test) changing.
function moveRemovedEntries(root, manifestIds, state, dateStr = todayStr(), onMove = () => {}) {
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  const moved = [];
  for (const id of Object.keys(state.entries || {})) {
    if (manifestIds.includes(id)) continue;
    const entryState = state.entries[id];
    for (const relPath of Object.keys(entryState.pngs || {})) {
      const rel = entryState.dir ? join(entryState.dir, relPath) : relPath;
      const src = join(outputRoot, rel);
      if (!existsSync(src)) continue;
      const dest = join(outputRoot, '_removed', dateStr, rel);
      mkdirSync(dirname(dest), { recursive: true });
      renameSync(src, dest);
      onMove(id, rel);
    }
    delete state.entries[id];
    moved.push(id);
  }
  return moved;
}

// ---------------------------------------------------------------------
// Change history (`_history/<run-id>/<same relative path>`, spec items
// 1-3): `promoteFile` moves a PNG here right before overwriting it on a
// `changed`/`drift` verdict; this section provides the run-id, retention
// (per-combo `history_keep` + whole-project `history_max_mb`) and the
// `runs.jsonl` run log `cmdPromote` appends to.
// ---------------------------------------------------------------------

// UTC `YYYY-MM-DD_HHMMSS`, one per `promote` invocation (spec item 1).
function runIdFor(date = new Date()) {
  const p2 = (n) => String(n).padStart(2, '0');
  return `${date.getUTCFullYear()}-${p2(date.getUTCMonth() + 1)}-${p2(date.getUTCDate())}_${p2(date.getUTCHours())}${p2(date.getUTCMinutes())}${p2(date.getUTCSeconds())}`;
}

function historyRunIds(outputRoot) {
  const historyRoot = join(outputRoot, '_history');
  if (!existsSync(historyRoot)) return [];
  return readdirSync(historyRoot, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();
}

// Every historical version of one combo (`relPath`, OS-native separators),
// oldest first -- the run-id's `YYYY-MM-DD_HHMMSS` format sorts
// lexicographically = chronologically, so no separate timestamp parse.
function historyVersionsFor(outputRoot, relPath) {
  return historyRunIds(outputRoot)
    .filter((runId) => existsSync(join(outputRoot, '_history', runId, relPath)))
    .map((runId) => ({ runId, path: join('_history', runId, relPath).split(sep).join('/') }));
}

function dirSizeBytes(dir) {
  if (!existsSync(dir)) return 0;
  let total = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    total += entry.isDirectory() ? dirSizeBytes(full) : statSync(full).size;
  }
  return total;
}

// Removes now-empty directories under `dir`, bottom-up, never `dir` itself
// (called with `_history` itself as `dir`, which is fine left empty).
function pruneEmptyDirs(dir) {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const full = join(dir, entry.name);
    pruneEmptyDirs(full);
    if (readdirSync(full).length === 0) rmSync(full, { recursive: true });
  }
}

// Retention (spec item 2): per-combo `history_keep` (default 5, oldest
// versions deleted first) for every combo `cmdPromote` touched this run,
// then a whole-project `history_max_mb` size cap (default 1024, oldest RUN
// folders deleted first, `currentRunId`'s folder never touched), then a
// sweep for run folders either prune left empty.
function enforceHistoryRetention(outputRoot, config, currentRunId, touchedRelPaths) {
  const historyRoot = join(outputRoot, '_history');
  if (!existsSync(historyRoot)) return;
  const keep = typeof config.history_keep === 'number' ? config.history_keep : 5;
  const maxBytes = (typeof config.history_max_mb === 'number' ? config.history_max_mb : 1024) * 1024 * 1024;

  for (const relPath of touchedRelPaths) {
    const versions = historyVersionsFor(outputRoot, relPath);
    const excess = versions.length - keep;
    for (let i = 0; i < excess; i++) {
      rmSync(join(outputRoot, versions[i].path.split('/').join(sep)), { force: true });
    }
  }

  pruneEmptyDirs(historyRoot);

  const runIds = historyRunIds(outputRoot).filter((id) => id !== currentRunId);
  while (dirSizeBytes(historyRoot) > maxBytes && runIds.length) {
    const oldest = runIds.shift();
    rmSync(join(historyRoot, oldest), { recursive: true, force: true });
  }
}

function appendRunLog(outputRoot, record) {
  mkdirSync(outputRoot, { recursive: true });
  appendFileSync(join(outputRoot, 'runs.jsonl'), `${JSON.stringify(record)}\n`);
}

function readRunsJsonl(outputRoot) {
  const path = join(outputRoot, 'runs.jsonl');
  if (!existsSync(path)) return [];
  return readFileSync(path, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

// Incoming filenames are `<entryId>__<rest>.png`, written by a driver into
// `.screens/.incoming/<platform>/` (drivers land in a later delivery stage;
// this promote step is generic over whatever a driver produces in that
// shape). `<rest>` becomes the filename inside the manifest entry's output
// directory (Output layout, plan's "Per-project files" table).
function cmdPromote(args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  const platform = argValue(args, '--platform') || (config.platforms && config.platforms[0]);
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  state.entries = state.entries || {};

  const diffTolerance = typeof config.diff_tolerance === 'number' ? config.diff_tolerance : 0.0001;
  const hasCompare = commandOnPath('compare');

  const startedAt = new Date();
  const runId = runIdFor(startedAt);
  const touchedRelPaths = new Set();
  const changedDetails = [];
  const newDetails = [];

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
      const targetPath = join(outputRoot, relPath);
      state.entries[id] = state.entries[id] || {};
      state.entries[id].pngs = state.entries[id].pngs || {};
      const prevHash = state.entries[id].pngs[relPath];
      const prevFingerprint = state.entries[id].fingerprint;
      const historyPath = join(outputRoot, '_history', runId, relPath);
      const { changed: didChange, hash, tolerated: didTolerate, historized } = promoteFile(
        join(incomingDir, file), targetPath, prevHash, { diffTolerance, hasCompare, historyPath },
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
      // Per-combination line (stage (f) follow-up 2): `<combo>` is the
      // capture filename minus the leading `<id>__` and the `.png`
      // extension (`state__role__viewport__theme[__locale]`), so a caller
      // that needs the tolerance-aware verdict for one exact combo -- not
      // just "this entry, some combo" -- can parse it, e.g. /delegate's
      // Phase 5 after-screenshot step deciding "unchanged" from this result
      // instead of a raw sha256 compare.
      const combo = rest.replace(/\.png$/, '');
      const forwardPath = relPath.split(sep).join('/');
      if (entry.known_nondeterministic) {
        knownNondeterministic++;
        lines.push(`PROMOTE_ENTRY ${id} ${combo} known_nondeterministic (${entry.known_nondeterministic})`);
      } else if (isDrift) {
        drift++;
        lines.push(`PROMOTE_ENTRY ${id} ${combo} drift`);
        if (historized) {
          touchedRelPaths.add(relPath);
          changedDetails.push({
            id, combo, path: forwardPath, verdict: 'drift',
            history_path: join('_history', runId, relPath).split(sep).join('/'),
          });
        }
      } else if (didTolerate) {
        tolerated++;
        lines.push(`PROMOTE_ENTRY ${id} ${combo} tolerated`);
      } else if (didChange) {
        // `prevHash` absent (rather than merely different) means this PNG
        // was never promoted before: the index's run summary (plan step 3)
        // distinguishes a brand-new capture from a recapture of a known one.
        if (prevHash) {
          changed++;
          lines.push(`PROMOTE_ENTRY ${id} ${combo} changed`);
          if (historized) {
            touchedRelPaths.add(relPath);
            changedDetails.push({
              id, combo, path: forwardPath, verdict: 'changed',
              history_path: join('_history', runId, relPath).split(sep).join('/'),
            });
          }
        } else {
          newCount++;
          lines.push(`PROMOTE_ENTRY ${id} ${combo} new`);
          newDetails.push({ id, combo, path: forwardPath });
        }
      } else {
        unchanged++;
        lines.push(`PROMOTE_ENTRY ${id} ${combo} unchanged`);
      }
    }
  }

  enforceHistoryRetention(outputRoot, config, runId, [...touchedRelPaths]);

  const manifestIds = manifest.entries.map((e) => e.id);
  const removedDetails = [];
  const removed = moveRemovedEntries(root, manifestIds, state, todayStr(), (id, rel) => {
    removedDetails.push({ id, path: rel.split(sep).join('/') });
  });
  for (const id of removed) lines.push(`PROMOTE_REMOVED ${id}`);

  const commit = (spawnSync('git', ['-C', root, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).stdout || '').trim() || null;

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
    commit,
  };

  writeJson(join(root, '.screens/state.json'), state);

  // Run log (spec item 3): one JSON line per promote invocation, read back
  // by `index` for the catalog's "Verlauf" (change history) section.
  appendRunLog(outputRoot, {
    run_id: runId,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    commit,
    platform: platform || null,
    counts: {
      new: newCount, changed, unchanged, tolerated, drift,
      removed: removed.length, failed: (state.last_run && state.last_run.failed) || 0,
    },
    changed: changedDetails,
    new: newDetails,
    removed: removedDetails,
  });

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
function cmdMigrateLayout(_args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
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
      const oldPath = join(outputRoot, oldDir, filename);
      if (!parts.state) {
        // Not a recognized capture filename shape: keep it untouched.
        newPngs[filename] = hash;
        continue;
      }
      const { relPath } = buildScreenshotPath(config, entry, entry.platform || defaultPlatform, parts);
      if (existsSync(oldPath) && resolve(oldPath) !== resolve(join(outputRoot, relPath))) {
        const newPath = join(outputRoot, relPath);
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

// Shared by `resolveMarketingGradient`/`resolveMarketingFont` below: the
// DESIGN.md-named token file's raw text, or null when DESIGN.md or the
// file it names is missing (same resolution `resolveMarketingBackground`
// does, extracted once instead of duplicated a second time).
function readMarketingTokenText(root) {
  const designPath = join(root, 'DESIGN.md');
  if (!existsSync(designPath)) return null;
  const designText = readFileSync(designPath, 'utf8');
  const fileMatch = /\b([\w./-]+\.(?:css|scss|json|ts|js))\b/.exec(designText);
  if (!fileMatch) return null;
  const tokenPath = join(root, fileMatch[1]);
  if (!existsSync(tokenPath)) return null;
  return readFileSync(tokenPath, 'utf8');
}

// Darkens a `#rrggbb` hex color by `amount` (0-1) for the hex-only gradient
// fallback below; an unparsable value passes through unchanged.
function darkenHex(hex, amount) {
  const m = /^#?([0-9a-fA-F]{6})$/.exec(hex);
  if (!m) return hex;
  const num = parseInt(m[1], 16);
  const channel = (shift) => Math.max(0, Math.round(((num >> shift) & 255) * (1 - amount)));
  return '#' + [channel(16), channel(8), channel(0)].map((c) => c.toString(16).padStart(2, '0')).join('');
}

// Brand gradient (App-Store-grade marketing render, "Background" spec):
// a token file expressing its scale in `oklch()` (Tailwind 4 style, e.g. a
// `--color-gray-900`/`--color-gray-950` pair) has its two darkest matching
// tokens passed straight through as CSS -- `oklch()` is valid inside
// `linear-gradient()` in any Chromium recent enough to run Playwright, so
// no color-space math is needed here. A project without such a scale (or
// without DESIGN.md at all) falls back to `resolveMarketingBackground`'s
// single hex swatch plus a darkened variant, so it still gets a 2-stop
// gradient instead of a flat fill.
function resolveMarketingGradient(root) {
  const tokenText = readMarketingTokenText(root);
  if (tokenText) {
    const matches = [...tokenText.matchAll(/--([\w-]*(?:gray|primary|accent|brand)[\w-]*)\s*:\s*(oklch\([^)]+\))/gi)];
    const withWeight = matches
      .map((m) => ({ value: m[2], weight: parseInt((/-(\d{2,3})\b/.exec(m[1]) || [])[1] || '-1', 10) }))
      .filter((t) => t.weight >= 0)
      .sort((a, b) => b.weight - a.weight);
    if (withWeight.length >= 2) {
      return `linear-gradient(160deg, ${withWeight[0].value} 0%, ${withWeight[1].value} 100%)`;
    }
  }
  const solid = resolveMarketingBackground(root);
  return `linear-gradient(160deg, ${solid} 0%, ${darkenHex(solid, 0.18)} 100%)`;
}

// Layout resolution (config's "marketing.layout" + per-entry override):
// "browser" or "browser-phone", global default falling back to "browser".
function resolveMarketingLayout(config, entry) {
  const marketingConfig = config.marketing || {};
  return entry.layout || marketingConfig.layout || 'browser';
}

// Headline font (Typography spec: "headline in the brand font"). Reads
// `--font-sans` (or an equivalent JSON `"font-sans"` key) out of the same
// token file `resolveMarketingGradient` reads, and walks `public/fonts` +
// `resources/fonts` for local `.woff2` files (no CDN, per the spec) whose
// filename says "regular" / "semibold"|"bold". Generic over any project:
// zeit's own `resources/fonts/inter/inter-regular.woff2` +
// `inter-semibold.woff2` resolve this way, nothing zeit-specific here.
function resolveMarketingFont(root) {
  const tokenText = readMarketingTokenText(root);
  const familyMatch = tokenText && (
    /--font-sans\s*:\s*['"]?([\w -]+)['"]?/i.exec(tokenText)
    || /"font-sans"\s*:\s*"([\w -]+)"/i.exec(tokenText)
  );
  const family = familyMatch ? familyMatch[1].trim() : 'system-ui';

  const files = [];
  for (const dir of ['public/fonts', 'resources/fonts']) {
    const abs = join(root, dir);
    if (!existsSync(abs)) continue;
    (function walk(d) {
      let entries;
      try {
        entries = readdirSync(d, { withFileTypes: true });
      } catch {
        return;
      }
      for (const entry of entries) {
        const full = join(d, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (/\.woff2?$/i.test(entry.name)) files.push(full);
      }
    })(abs);
  }
  return {
    family,
    regularPath: files.find((f) => /regular/i.test(f)) || null,
    boldPath: files.find((f) => /semibold|bold/i.test(f)) || null,
  };
}

// Optional small wordmark above the headline (Typography spec): the first
// `.svg` file under `public/` whose name contains "logo", or null. Shallow
// heuristic on purpose (same class as the font/gradient resolvers above):
// this only ever picks a candidate asset, never generates one.
function resolveMarketingLogo(root) {
  const publicDir = join(root, 'public');
  if (!existsSync(publicDir)) return null;
  const matches = [];
  (function walk(d) {
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(d, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/logo/i.test(entry.name) && /\.svg$/i.test(entry.name)) matches.push(full);
    }
  })(publicDir);
  return matches[0] || null;
}

// 2x marketing source set (config's "marketing.source_scale", default 2):
// `capture.spec.ts` writes `<entryId>__desktop.png` / `<entryId>__mobile.png`
// straight into `.screens/.marketing-src/` for every entry listed in
// `marketing.entries` (desktop + mobile, light theme, filled state only --
// the combo the marketing renders actually use), bypassing `promote`
// entirely so the catalog PNGs never change. Either file may be absent
// (an older capture run, or `source_scale` disabled): the caller falls
// back to the 1x catalog source via `findMarketingSourcePng`.
function findMarketingSourceSet(root, entryId) {
  const dir = join(root, '.screens/.marketing-src');
  const desktopPath = join(dir, `${entryId}__desktop.png`);
  const mobilePath = join(dir, `${entryId}__mobile.png`);
  return {
    desktop: existsSync(desktopPath) ? desktopPath : null,
    mobile: existsSync(mobilePath) ? mobilePath : null,
  };
}

function hashFile(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

// Contrast: the headline and the optional logo need to flip between white
// (dark background) and near-black (light background) depending on what
// `resolveMarketingGradient` actually resolved -- a dark-on-dark logo (e.g.
// zeit's own near-black `#0b0b0b` wordmark against the near-black gradient
// its own oklch gray-950/900 tokens produce) is otherwise unreadable.
// Reads the first color stop's lightness only, since that is where the
// logo/headline sit.
function backgroundIsDark(css) {
  const oklchMatch = /oklch\(\s*([\d.]+)/.exec(css);
  if (oklchMatch) return parseFloat(oklchMatch[1]) < 0.5;
  const hexMatch = /#([0-9a-fA-F]{6})/.exec(css);
  if (hexMatch) {
    const num = parseInt(hexMatch[1], 16);
    const luminance = (0.299 * ((num >> 16) & 255) + 0.587 * ((num >> 8) & 255) + 0.114 * (num & 255)) / 255;
    return luminance < 0.5;
  }
  return false;
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

// Resolves the source(s) a marketing entry frames: the 2x source set
// (`marketing.source_scale`, see `findMarketingSourceSet`) when present,
// falling back to the 1x catalog PNG `findMarketingSourcePng` already
// selected (older capture run, or `source_scale` disabled). Null when
// neither exists.
function resolveEntrySources(root, state, sourceId) {
  const scaleSet = findMarketingSourceSet(root, sourceId);
  if (scaleSet.desktop) {
    return {
      desktopPath: scaleSet.desktop,
      mobilePath: scaleSet.mobile,
      hash: hashFile(scaleSet.desktop) + (scaleSet.mobile ? hashFile(scaleSet.mobile) : ''),
    };
  }
  const fallback = findMarketingSourcePng(state, sourceId);
  if (!fallback) return null;
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  return { desktopPath: join(outputRoot, fallback.relPath), mobilePath: null, hash: fallback.hash };
}

function cmdMarketing(_args, root = process.cwd(), renderer = defaultMarketingRenderer) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  state.marketing = state.marketing || {};
  const entries = (config.marketing && config.marketing.entries) || [];
  const locales = (config.marketing && config.marketing.locales) || ['de'];
  const formats = (config.marketing && config.marketing.formats) || {};
  const defaultPlatform = (config.platforms && config.platforms[0]) || 'web';
  const background = resolveMarketingGradient(root);
  const domain = (config.marketing && config.marketing.domain) || 'app.example.com';
  const font = resolveMarketingFont(root);
  const logoPath = resolveMarketingLogo(root);

  const jobs = [];
  const jobMeta = []; // parallel to jobs: {key, dir, targetPath, reviewed}
  let skipped = 0;
  let notesCount = 0;

  entries.forEach((entry, idx) => {
    const platform = entry.platform || defaultPlatform;
    const sourceId = entry.source || entry.id;
    const source = resolveEntrySources(root, state, sourceId);
    for (const locale of locales) {
      const headline = entry.headlines && entry.headlines[locale];
      if (!headline || !headline.text) {
        lines.push(`MARKETING_NOTE ${entry.id} ${locale} no headline configured`);
        notesCount++;
        continue;
      }
      if (!source) {
        lines.push(`MARKETING_NOTE ${entry.id} ${locale} no catalog PNG found for source "${sourceId}"`);
        notesCount++;
        continue;
      }
      const format = entry.format || formats[platform] || '1920x1080';
      const reviewed = !!headline.reviewed;
      const dir = marketingTargetDir(platform, locale, format, reviewed);
      const filename = `${pad2(idx + 1)}-${entry.id}.png`;
      const relPath = join(dir, filename);
      const targetPath = join(outputRoot, relPath);
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
          rmSync(join(outputRoot, prevRecord.relPath), { force: true });
        } catch {
          // best-effort cleanup only
        }
      }

      // "browser-phone" needs a mobile source; a 1x-fallback or a missing
      // mobile capture degrades to "browser" rather than rendering a phone
      // frame around a null image.
      const layout = source.mobilePath ? resolveMarketingLayout(config, entry) : 'browser';

      const dark = backgroundIsDark(background);

      jobs.push({
        id: entry.id, locale, format, headline: headline.text, background, layout, domain,
        desktopSrc: source.desktopPath, mobileSrc: layout === 'browser-phone' ? source.mobilePath : null,
        fontFamily: font.family, regularFontPath: font.regularPath, boldFontPath: font.boldPath,
        logoPath, textColor: dark ? '#ffffff' : '#1d1d1f', logoInvert: dark,
        // Depth (Background spec, round 2): a soft radial glow behind the
        // window so the stage isn't a flat fill; polarity follows the same
        // dark/light contrast flip as textColor/logoInvert above.
        highlightColor: dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(0, 0, 0, 0.04)',
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

// Attaches each item's `_history/*/<relPath>` versions (Change history spec
// item 4, "n Versionen" badge + per-item before/after), newest first;
// `history` is `[]` for an item with no historical version. Separate from
// `buildIndexItems` above (manifest/state only, no filesystem) since this
// one has to read `outputRoot`.
function attachIndexHistory(items, outputRoot) {
  return items.map((item) => ({
    ...item,
    history: historyVersionsFor(outputRoot, item.path.split('/').join(sep))
      .slice()
      .reverse()
      .map((v) => ({ run_id: v.runId, path: v.path })),
  }));
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

// Per-project summary a project's own `index` run leaves next to its
// `index.html`, read by `regenerateTopIndex` below to build the top-level
// `~/Developer/screens/index.html` without re-parsing every project's full
// `state.json`.
function buildCatalogSummary(config, state, items) {
  const platforms = [...new Set(items.map((i) => i.platform))].sort();
  return {
    project: config.project || null,
    platforms,
    count: items.length,
    last_run: state.last_run || null,
  };
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Static, dependency-free top-level index (user decision: "static, no
// deps, relative links"): one row per project directory under
// `centralRoot` that carries a `catalog.json`, linking to that project's
// own `index.html` via a relative `./<project>/index.html` href.
function buildTopIndexHtml(projects) {
  const rows = projects.map((p) => {
    const name = escapeHtml(p.project || p.dir);
    const platforms = escapeHtml((p.platforms || []).join(', '));
    const count = p.count || 0;
    const lastRun = escapeHtml((p.last_run && p.last_run.date) || '');
    const changedCount = (p.last_run && p.last_run.updated) || 0;
    const link = `./${p.dir}/index.html`;
    return `    <tr><td>${name}</td><td>${platforms}</td><td>${count}</td><td>${lastRun}</td><td>${changedCount}</td><td><a href="${link}">View</a></td></tr>`;
  }).join('\n');
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Screens</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 0.5rem; text-align: left; }
th { background: #f5f5f7; }
</style>
</head>
<body>
<h1>Screens</h1>
<table>
  <thead><tr><th>Project</th><th>Platforms</th><th>Images</th><th>Last run</th><th>Changed</th><th></th></tr></thead>
  <tbody>
${rows}
  </tbody>
</table>
</body>
</html>
`;
}

// Regenerates `<centralRoot>/index.html` from every `<centralRoot>/*/catalog.json`
// (plan step 3, top-level index). Called at the end of every `index` run;
// a project using `config.output_dir` to live outside `centralRoot` simply
// does not appear here, same as it not appearing under the central folder
// at all.
function regenerateTopIndex(centralRoot = join(os.homedir(), 'Developer', 'screens')) {
  let entries;
  try {
    entries = readdirSync(centralRoot, { withFileTypes: true });
  } catch {
    return 0;
  }
  const projects = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const catalog = readJson(join(centralRoot, entry.name, 'catalog.json'), null);
    if (!catalog) continue;
    projects.push({ ...catalog, dir: entry.name });
  }
  projects.sort((a, b) => (a.project || a.dir).localeCompare(b.project || b.dir));
  mkdirSync(centralRoot, { recursive: true });
  writeFileSync(join(centralRoot, 'index.html'), buildTopIndexHtml(projects));
  return projects.length;
}

function cmdIndex(_args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  const manifest = readJson(join(root, '.screens/manifest.json'), { entries: [] });
  const state = readJson(join(root, '.screens/state.json'), { entries: {} });
  const templatePath = join(dirname(fileURLToPath(import.meta.url)), '..', 'templates', 'index.html');
  if (!existsSync(templatePath)) {
    lines.push('INDEX_RESULT=FAIL (templates/index.html not found)');
    return lines;
  }

  const items = attachIndexHistory(buildIndexItems(manifest, state), outputRoot);
  const marketing = buildIndexMarketing(state);
  const runs = readRunsJsonl(outputRoot).slice().reverse(); // newest first (Verlauf)
  const data = { items, marketing, last_run: state.last_run || {}, runs };

  const template = readFileSync(templatePath, 'utf8');
  const html = template.replace('__SCREENS_DATA__', () => JSON.stringify(data));

  const outPath = join(outputRoot, 'index.html');
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, html);

  const catalog = buildCatalogSummary(config, state, items);
  writeJson(join(outputRoot, 'catalog.json'), catalog);
  const projectCount = regenerateTopIndex();

  lines.push(`INDEX_ITEMS=${items.length}`);
  lines.push(`INDEX_MARKETING=${marketing.length}`);
  lines.push(`INDEX_RESULT=OK path=${outPath}`);
  lines.push(`TOP_INDEX_RESULT=OK projects=${projectCount}`);
  return lines;
}

// ---------------------------------------------------------------------
// migrate-output: one-time move of an existing project-local `screenshots/`
// tree into the resolved central output root (Output root resolution),
// preserving every inner path. Distinct from `migrate-layout` above: that
// one restructures paths WITHIN whatever root already holds the catalog,
// this one only relocates the root itself.
// ---------------------------------------------------------------------

// `renameSync` across filesystems throws EXDEV (e.g. a project on a
// different volume from `~/Developer/screens`); falls back to copy+unlink
// so the move still completes instead of failing the whole migration.
function moveFile(src, dest) {
  mkdirSync(dirname(dest), { recursive: true });
  try {
    renameSync(src, dest);
  } catch (err) {
    if (err && err.code === 'EXDEV') {
      copyFileSync(src, dest);
      rmSync(src, { force: true });
    } else {
      throw err;
    }
  }
}

function cmdMigrateOutput(_args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const { outputRoot } = ensureProjectConfigured(root, config);
  const srcDir = join(root, 'screenshots');
  if (!existsSync(srcDir)) {
    lines.push(`MIGRATE_OUTPUT_RESULT=SKIP (no screenshots/ at ${srcDir})`);
    return lines;
  }
  if (resolve(srcDir) === resolve(outputRoot)) {
    lines.push('MIGRATE_OUTPUT_RESULT=SKIP (output_dir already points at screenshots/)');
    return lines;
  }
  const relFiles = listDirFiles(srcDir, '.');
  const sampleRel = relFiles[0] || null;
  const sampleHashBefore = sampleRel ? hashFile(join(srcDir, sampleRel)) : null;
  let moved = 0;
  for (const relPath of relFiles) {
    moveFile(join(srcDir, relPath), join(outputRoot, relPath));
    moved++;
  }
  const sampleHashAfter = sampleRel ? hashFile(join(outputRoot, sampleRel)) : null;
  const sampleVerified = !sampleRel || sampleHashBefore === sampleHashAfter;
  rmSync(srcDir, { recursive: true, force: true });
  lines.push(`MIGRATE_OUTPUT_RESULT=OK moved=${moved} sample_verified=${sampleVerified}`);
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
    'android-navigate': cmdAndroidNavigate,
    'macos-export': cmdMacosExport,
    promote: cmdPromote,
    'migrate-layout': cmdMigrateLayout,
    'migrate-output': cmdMigrateOutput,
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
  expandProjectRoot,
  expandHome,
  findScreensRoots,
  projectFamilyDir,
  deriveProjectSlug,
  resolveScreensOutputRoot,
  ensureProjectConfigured,
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
  xcresultExportAttachmentsArgs,
  stripXcresultSuffix,
  mapXcresultExportToIncoming,
  cmdMacosExport,
  androidAvdName,
  androidEmulatorPort,
  resolveAndroidSdkRoot,
  androidToolPaths,
  resolveAvdmanagerPath,
  androidToolsPreflight,
  probeAndroidTools,
  avdExists,
  findInstalledSystemImages,
  androidAvdCreateShellCmd,
  androidDemoModeArgs,
  androidThemeArgs,
  androidExplicitIntentArgs,
  androidDeepLinkUrl,
  waitForAndroidBoot,
  androidDeviceSetup,
  deviceSetupHook,
  laravelDbGuard,
  bunDbGuard,
  composePhpIniScanDir,
  phpFixedClockEnv,
  laravelPerfEnv,
  laravelSessionEnv,
  pidFilePath,
  androidAppUrlEnv,
  playwrightWorkers,
  computeSeedFingerprint,
  generateDemoPassword,
  ensureGitignoreEntry,
  ensureSecretsFile,
  secretConfigGuard,
  demoPasswordEnv,
  cmdUp,
  killPortListeners,
  cmdDown,
  cmdAndroidNavigate,
  commandOnPath,
  readPngDimensions,
  defaultCompareRunner,
  parseAeCount,
  promoteFile,
  deviceClassFor,
  parseCaptureFilename,
  buildScreenshotPath,
  moveRemovedEntries,
  runIdFor,
  historyRunIds,
  historyVersionsFor,
  dirSizeBytes,
  pruneEmptyDirs,
  enforceHistoryRetention,
  appendRunLog,
  readRunsJsonl,
  cmdPromote,
  cmdMigrateLayout,
  marketingTargetDir,
  marketingNeedsRender,
  resolveMarketingBackground,
  resolveMarketingGradient,
  darkenHex,
  backgroundIsDark,
  resolveMarketingLayout,
  resolveMarketingFont,
  resolveMarketingLogo,
  findMarketingSourceSet,
  resolveEntrySources,
  findMarketingSourcePng,
  defaultMarketingRenderer,
  cmdMarketing,
  parsePromotedFilename,
  buildIndexItems,
  attachIndexHistory,
  buildIndexMarketing,
  buildCatalogSummary,
  buildTopIndexHtml,
  regenerateTopIndex,
  cmdIndex,
  moveFile,
  cmdMigrateOutput,
  computeCommandHash,
  cmdTrust,
  affectedIds,
  cmdAffected,
  readJson,
  writeJson,
};
