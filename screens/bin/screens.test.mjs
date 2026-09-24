// screens.test.mjs: one test per branch named in the plan step 2 verify
// criterion. Run with `node --test screens/bin/`.
//
// Each test constructs a throwaway fixture under a fresh mkdtemp() dir
// (never the repo itself) and calls the exported functions directly, so
// the Laravel/Bun DB guard tests can inject a stub command runner instead
// of spawning `php`.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync, existsSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

import {
  expandProjectRoot,
  planEntries,
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
  avdExists,
  findInstalledSystemImages,
  androidAvdCreateShellCmd,
  androidDemoModeArgs,
  androidThemeArgs,
  waitForAndroidBoot,
  androidDeviceSetup,
  cmdUp,
  laravelDbGuard,
  composePhpIniScanDir,
  phpFixedClockEnv,
  laravelPerfEnv,
  playwrightWorkers,
  computeSeedFingerprint,
  readPngDimensions,
  promoteFile,
  deviceClassFor,
  buildScreenshotPath,
  moveRemovedEntries,
  cmdPromote,
  cmdMigrateLayout,
  cmdPlan,
  cmdTrust,
  computeCommandHash,
  marketingTargetDir,
  resolveMarketingBackground,
  cmdMarketing,
  parsePromotedFilename,
  buildIndexItems,
  buildIndexMarketing,
  cmdIndex,
  affectedIds,
  writeJson,
  readJson,
} from './screens.mjs';

// Minimal valid PNG byte layout for readPngDimensions: 8-byte signature +
// 4-byte chunk length + 4-byte "IHDR" type + 4-byte width + 4-byte height
// (big-endian), the rest is irrelevant filler.
function fakePng(width, height, filler = 'x') {
  const buf = Buffer.alloc(30, filler);
  buf.writeUInt32BE(width, 16);
  buf.writeUInt32BE(height, 20);
  return buf;
}

function fixture() {
  return mkdtempSync(join(tmpdir(), 'screens-test-'));
}

function writeFile(root, relPath, content) {
  const full = join(root, relPath);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, content);
}

// --- expandProjectRoot: `${PROJECT_ROOT}` placeholder --------------------

test('expandProjectRoot: nested launch_args expansion', () => {
  const root = fixture();
  const entry = { launch_args: ['--import', '${PROJECT_ROOT}/.screens/mac/fixtures/cube.stl'] };
  const expanded = expandProjectRoot(entry, root);
  assert.equal(expanded.launch_args[1], `${root}/.screens/mac/fixtures/cube.stl`);
});

test('expandProjectRoot: unknown placeholder left untouched', () => {
  const root = fixture();
  const value = { extra_args: ['-Flag', '${OTHER_PLACEHOLDER}'] };
  const expanded = expandProjectRoot(value, root);
  assert.equal(expanded.extra_args[1], '${OTHER_PLACEHOLDER}');
});

// --- plan: new entry -> planned -----------------------------------------

test('plan: new entry -> planned (new)', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  const manifest = { entries: [{ id: 'home', sources: ['view.blade.php'] }] };
  const state = { entries: {} };
  const [r] = planEntries(root, manifest, state, false);
  assert.equal(r.status, 'new');
});

// --- plan: unchanged entry -> skipped ------------------------------------

test('plan: unchanged entry -> unchanged (skipped)', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  const manifest = { entries: [{ id: 'home', sources: ['view.blade.php'] }] };
  const fingerprint = planEntries(root, manifest, { entries: {} }, false)[0].fingerprint;
  writeFile(root, 'screenshots/web/area/home/filled.png', 'png-bytes');
  const state = {
    entries: {
      home: { fingerprint, dir: 'web/area/home', pngs: { 'filled.png': 'whatever' } },
    },
  };
  const [r] = planEntries(root, manifest, state, false);
  assert.equal(r.status, 'unchanged');
});

// --- plan: source change -> stale ----------------------------------------

test('plan: source file changed -> stale', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  const manifest = { entries: [{ id: 'home', sources: ['view.blade.php'] }] };
  const fingerprint = planEntries(root, manifest, { entries: {} }, false)[0].fingerprint;
  writeFile(root, 'screenshots/web/area/home/filled.png', 'png-bytes');
  const state = { entries: { home: { fingerprint, dir: 'web/area/home', pngs: { 'filled.png': 'x' } } } };
  writeFile(root, 'view.blade.php', 'a-changed');
  const [r] = planEntries(root, manifest, state, false);
  assert.equal(r.status, 'stale');
});

// --- plan: global invalidator (lockfile) change -> all stale -------------

test('plan: global_sources (lockfile) change -> all entries stale', () => {
  const root = fixture();
  writeFile(root, 'view-a.blade.php', 'a');
  writeFile(root, 'view-b.blade.php', 'b');
  writeFile(root, 'composer.lock', 'lock-v1');
  writeJson(join(root, '.screens/config.json'), { global_sources: ['composer.lock'] });
  const manifest = {
    entries: [
      { id: 'a', sources: ['view-a.blade.php'] },
      { id: 'b', sources: ['view-b.blade.php'] },
    ],
  };
  const before = planEntries(root, manifest, { entries: {} }, false);
  writeFile(root, 'screenshots/web/area/a/filled.png', 'x');
  writeFile(root, 'screenshots/web/area/b/filled.png', 'x');
  const state = {
    entries: {
      a: { fingerprint: before[0].fingerprint, dir: 'web/area/a', pngs: { 'filled.png': 'x' } },
      b: { fingerprint: before[1].fingerprint, dir: 'web/area/b', pngs: { 'filled.png': 'x' } },
    },
  };
  writeFile(root, 'composer.lock', 'lock-v2');
  const after = planEntries(root, manifest, state, false);
  assert.ok(after.every((r) => r.status === 'stale'), 'every entry should be stale after a lockfile bump');
});

// --- plan: missing PNG -> planned ----------------------------------------

test('plan: fingerprint unchanged but PNG missing -> missing_png (planned)', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  const manifest = { entries: [{ id: 'home', sources: ['view.blade.php'] }] };
  const fingerprint = planEntries(root, manifest, { entries: {} }, false)[0].fingerprint;
  const state = { entries: { home: { fingerprint, dir: 'web/area/home', pngs: { 'filled.png': 'x' } } } };
  // no PNG written on disk
  const [r] = planEntries(root, manifest, state, false);
  assert.equal(r.status, 'missing_png');
});

// --- plan: --full -> all planned -----------------------------------------

test('plan: --full recaptures an otherwise unchanged entry', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  const manifest = { entries: [{ id: 'home', sources: ['view.blade.php'] }] };
  const fingerprint = planEntries(root, manifest, { entries: {} }, false)[0].fingerprint;
  writeFile(root, 'screenshots/web/area/home/filled.png', 'png-bytes');
  const state = { entries: { home: { fingerprint, dir: 'web/area/home', pngs: { 'filled.png': 'x' } } } };
  const [r] = planEntries(root, manifest, state, true);
  assert.equal(r.status, 'stale');
});

// --- promote: removed entry -> moved to _removed --------------------------

test('promote: entry removed from manifest -> PNGs moved to _removed/<date>/', () => {
  const root = fixture();
  writeFile(root, 'screenshots/web/area/gone/filled.png', 'bytes');
  const state = { entries: { gone: { dir: 'web/area/gone', fingerprint: 'x', pngs: { 'filled.png': 'x' } } } };
  const moved = moveRemovedEntries(root, [], state, '2026-09-24');
  assert.deepEqual(moved, ['gone']);
  assert.ok(existsSync(join(root, 'screenshots/_removed/2026-09-24/web/area/gone/filled.png')));
  assert.ok(!existsSync(join(root, 'screenshots/web/area/gone/filled.png')));
  assert.equal(state.entries.gone, undefined);
});

// --- promote: equal hash -> old file untouched (mtime unchanged) ---------

test('promote: identical bytes -> target file left untouched (mtime unchanged)', () => {
  const root = fixture();
  writeFile(root, 'incoming/entry__filled.png', 'same-bytes');
  const targetPath = join(root, 'screenshots/web/area/entry/filled.png');
  writeFile(root, 'screenshots/web/area/entry/filled.png', 'same-bytes');
  const prevHash = require_sha256('same-bytes');
  const before = statSync(targetPath).mtimeMs;
  const { changed } = promoteFile(join(root, 'incoming/entry__filled.png'), targetPath, prevHash);
  const after = statSync(targetPath).mtimeMs;
  assert.equal(changed, false);
  assert.equal(before, after);
});

// --- promote: different hash -> replaced ----------------------------------

test('promote: different bytes -> target file replaced', () => {
  const root = fixture();
  writeFile(root, 'incoming/entry__filled.png', 'new-bytes');
  const targetPath = join(root, 'screenshots/web/area/entry/filled.png');
  writeFile(root, 'screenshots/web/area/entry/filled.png', 'old-bytes');
  const prevHash = require_sha256('old-bytes');
  const { changed } = promoteFile(join(root, 'incoming/entry__filled.png'), targetPath, prevHash, { hasCompare: false });
  assert.equal(changed, true);
  assert.equal(readFileSync(targetPath, 'utf8'), 'new-bytes');
});

// --- promote: tolerance compare (diff_tolerance, ImageMagick compare) ------

test('promote: AE within diff_tolerance -> old file kept (tolerated)', () => {
  const root = fixture();
  const oldBuf = fakePng(1000, 1000, 'a');
  const newBuf = fakePng(1000, 1000, 'b');
  writeFile(root, 'incoming/entry__filled.png', newBuf);
  const targetPath = join(root, 'screenshots/web/area/entry/filled.png');
  writeFile(root, 'screenshots/web/area/entry/filled.png', oldBuf);
  const prevHash = createHash('sha256').update(oldBuf).digest('hex');
  // 50 differing pixels of 1,000,000 = 0.005%, under the default 0.01% tolerance.
  const compareRunner = () => ({ stderr: '50' });
  const { changed, tolerated, hash } = promoteFile(
    join(root, 'incoming/entry__filled.png'), targetPath, prevHash,
    { hasCompare: true, compareRunner },
  );
  assert.equal(changed, false);
  assert.equal(tolerated, true);
  assert.equal(hash, prevHash);
  assert.equal(readFileSync(targetPath).compare(oldBuf), 0, 'old file must stay untouched');
});

test('promote: AE above diff_tolerance -> target file replaced', () => {
  const root = fixture();
  const oldBuf = fakePng(1000, 1000, 'a');
  const newBuf = fakePng(1000, 1000, 'b');
  writeFile(root, 'incoming/entry__filled.png', newBuf);
  const targetPath = join(root, 'screenshots/web/area/entry/filled.png');
  writeFile(root, 'screenshots/web/area/entry/filled.png', oldBuf);
  const prevHash = createHash('sha256').update(oldBuf).digest('hex');
  // 5,000 of 1,000,000 pixels = 0.5%, above the default 0.01% tolerance.
  const compareRunner = () => ({ stderr: '5000' });
  const { changed, tolerated } = promoteFile(
    join(root, 'incoming/entry__filled.png'), targetPath, prevHash,
    { hasCompare: true, compareRunner },
  );
  assert.equal(changed, true);
  assert.equal(tolerated, false);
  assert.equal(readFileSync(targetPath).compare(newBuf), 0);
});

test('promote: ImageMagick missing -> byte-exact compare (no tolerance applied)', () => {
  const root = fixture();
  const oldBuf = fakePng(1000, 1000, 'a');
  const newBuf = fakePng(1000, 1000, 'b');
  writeFile(root, 'incoming/entry__filled.png', newBuf);
  const targetPath = join(root, 'screenshots/web/area/entry/filled.png');
  writeFile(root, 'screenshots/web/area/entry/filled.png', oldBuf);
  const prevHash = createHash('sha256').update(oldBuf).digest('hex');
  const compareRunner = () => {
    throw new Error('compareRunner must not be called when hasCompare is false');
  };
  const { changed, tolerated } = promoteFile(
    join(root, 'incoming/entry__filled.png'), targetPath, prevHash,
    { hasCompare: false, compareRunner },
  );
  assert.equal(changed, true);
  assert.equal(tolerated, false);
});

test('readPngDimensions reads width/height from IHDR bytes 16-23', () => {
  const buf = fakePng(1440, 900);
  assert.deepEqual(readPngDimensions(buf), { width: 1440, height: 900 });
});

// --- promote persists the fingerprint plan needs on the next run ---------

test('promote: persists entry fingerprint so a later plan call with no source changes reports unchanged', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'entry', platform: 'web', area: 'area', view: 'entry', sources: ['view.blade.php'] }],
  });
  writeJson(join(root, '.screens/state.json'), { entries: {} });
  writeFile(root, '.screens/.incoming/web/entry__filled__guest__1440x900__light.png', 'bytes');

  cmdPromote(['--platform', 'web'], root);

  const stateAfterPromote = readJson(join(root, '.screens/state.json'), {});
  assert.ok(stateAfterPromote.entries.entry.fingerprint, 'promote must store a fingerprint');

  const planLines = cmdPlan([], root);
  assert.ok(planLines.includes('PLAN_ENTRY entry unchanged'), planLines.join('\n'));
});

// --- promote: per-combination PROMOTE_ENTRY line (stage (f) follow-up 2) ---

test('promote: PROMOTE_ENTRY carries the combo and distinguishes unchanged from tolerated', () => {
  const root = fixture();
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'entry', platform: 'web', area: 'area', view: 'entry', sources: [] }],
  });
  const unchangedBuf = Buffer.from('same-bytes');
  const relPath = 'web/1440x900/area/entry/filled__guest__light.png';
  writeFile(root, join('screenshots', relPath), unchangedBuf);
  writeJson(join(root, '.screens/state.json'), {
    entries: { entry: { fingerprint: 'x', pngs: { [relPath]: require_sha256(unchangedBuf) } } },
  });
  writeFile(root, '.screens/.incoming/web/entry__filled__guest__1440x900__light.png', unchangedBuf);

  const lines = cmdPromote(['--platform', 'web'], root);

  assert.ok(lines.includes('PROMOTE_ENTRY entry filled__guest__1440x900__light unchanged'), lines.join('\n'));
});

// --- promote: known_nondeterministic entries excluded from changed/unchanged ---

test('promote: known_nondeterministic entry is reported separately, not counted as changed or unchanged', () => {
  const root = fixture();
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{
      id: 'reorderable', platform: 'web', area: 'area', view: 'reorderable', sources: [],
      known_nondeterministic: 'row order has no ORDER BY tie-break',
    }],
  });
  writeJson(join(root, '.screens/state.json'), { entries: {} });
  writeFile(root, '.screens/.incoming/web/reorderable__filled__guest__1440x900__light.png', 'bytes');

  const lines = cmdPromote(['--platform', 'web'], root);

  assert.ok(lines.some((l) => l === 'PROMOTE_ENTRY reorderable filled__guest__1440x900__light known_nondeterministic (row order has no ORDER BY tie-break)'), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('PROMOTE_RESULT=OK changed=0 unchanged=0 tolerated=0 removed=0 known_nondeterministic=1')), lines.join('\n'));
});

// --- drift reporting (step 1, --full only) ----------------------------------

test('promote --full: unchanged fingerprint + changed image -> drift, old fingerprint\'s prev PNG still written', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'same-content');
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'entry', platform: 'web', area: 'area', view: 'entry', sources: ['view.blade.php'] }],
  });
  const fingerprint = require_sha256('view.blade.php' + 'same-content');
  const relPath = 'web/1440x900/area/entry/filled__guest__light.png';
  const targetPath = join(root, 'screenshots', relPath);
  const oldBuf = fakePng(1000, 1000, 'a');
  const newBuf = fakePng(1000, 1000, 'b');
  writeFile(root, join('screenshots', relPath), oldBuf);
  writeJson(join(root, '.screens/state.json'), {
    entries: {
      entry: {
        fingerprint,
        pngs: { [relPath]: require_sha256(oldBuf) },
      },
    },
  });
  writeFile(root, '.screens/.incoming/web/entry__filled__guest__1440x900__light.png', newBuf);

  const lines = cmdPromote(['--platform', 'web', '--full'], root);

  assert.ok(lines.includes('PROMOTE_ENTRY entry filled__guest__1440x900__light drift'), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('PROMOTE_RESULT=OK changed=0 unchanged=0 tolerated=0 removed=0 known_nondeterministic=0 drift=1')), lines.join('\n'));
  assert.equal(readFileSync(targetPath).compare(newBuf), 0, 'truth wins: the new PNG is written despite being reported as drift');
});

test('promote --full: changed fingerprint + changed image -> changed, not drift', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'new-content');
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'entry', platform: 'web', area: 'area', view: 'entry', sources: ['view.blade.php'] }],
  });
  const relPath = 'web/1440x900/area/entry/filled__guest__light.png';
  const oldBuf = fakePng(1000, 1000, 'a');
  const newBuf = fakePng(1000, 1000, 'b');
  writeFile(root, join('screenshots', relPath), oldBuf);
  writeJson(join(root, '.screens/state.json'), {
    entries: {
      entry: {
        fingerprint: 'stale-fingerprint-from-before-the-source-edit',
        pngs: { [relPath]: require_sha256(oldBuf) },
      },
    },
  });
  writeFile(root, '.screens/.incoming/web/entry__filled__guest__1440x900__light.png', newBuf);

  const lines = cmdPromote(['--platform', 'web', '--full'], root);

  assert.ok(lines.includes('PROMOTE_ENTRY entry filled__guest__1440x900__light changed'), lines.join('\n'));
  assert.ok(!lines.some((l) => l.endsWith(' drift')), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('PROMOTE_RESULT=OK changed=1 unchanged=0 tolerated=0 removed=0 known_nondeterministic=0 drift=0')), lines.join('\n'));
});

// --- device-class path builder (Output layout) ------------------------------

test('buildScreenshotPath: viewport maps to device class, viewport drops out of the filename', () => {
  const config = { axes: { device_classes: { web: { '1440x900': 'desktop', '390x844': 'mobile' } } } };
  const entry = { area: 'app', view: 'dashboard' };
  const { relDir, relPath } = buildScreenshotPath(config, entry, 'web', {
    state: 'filled', role: 'admin', viewport: '1440x900', theme: 'light',
  });
  assert.equal(relDir, join('web', 'desktop', 'app', 'dashboard'));
  assert.equal(relPath, join('web', 'desktop', 'app', 'dashboard', 'filled__admin__light.png'));
});

test('buildScreenshotPath: locale suffix only when a locale part is present', () => {
  const config = { axes: { device_classes: { web: { '1440x900': 'desktop' } } } };
  const entry = { area: 'marketing', view: 'home' };
  const { relPath } = buildScreenshotPath(config, entry, 'web', {
    state: 'filled', role: 'guest', viewport: '1440x900', theme: 'light', locale: 'en',
  });
  assert.equal(relPath, join('web', 'desktop', 'marketing', 'home', 'filled__guest__light__en.png'));
});

test('deviceClassFor: unconfigured viewport falls back to itself', () => {
  const config = { axes: { device_classes: { web: { '1440x900': 'desktop' } } } };
  assert.equal(deviceClassFor(config, 'web', '999x999'), '999x999');
});

// --- migrate-layout: moves existing PNGs into device-class folders, keeps hash ---

test('cmdMigrateLayout: moves a flat-layout PNG to the device-class path, state.json key + hash updated', () => {
  const root = fixture();
  writeJson(join(root, '.screens/config.json'), {
    platforms: ['web'], axes: { device_classes: { web: { '1440x900': 'desktop' } } },
  });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'dashboard', platform: 'web', area: 'app', view: 'dashboard' }],
  });
  const oldRel = 'web/app/dashboard/filled__admin__1440x900__light.png';
  writeFile(root, `screenshots/${oldRel}`, 'png-bytes');
  const hash = require_sha256('png-bytes');
  writeJson(join(root, '.screens/state.json'), {
    entries: { dashboard: { dir: 'web/app/dashboard', fingerprint: 'x', pngs: { 'filled__admin__1440x900__light.png': hash } } },
  });

  const lines = cmdMigrateLayout([], root);

  assert.ok(lines.some((l) => l.startsWith('MIGRATE_RESULT=OK moved=1')), lines.join('\n'));
  const newRel = 'web/desktop/app/dashboard/filled__admin__light.png';
  assert.ok(!existsSync(join(root, 'screenshots', oldRel)));
  assert.ok(existsSync(join(root, 'screenshots', newRel)));
  const state = readJson(join(root, '.screens/state.json'), {});
  assert.equal(state.entries.dashboard.dir, undefined);
  assert.equal(state.entries.dashboard.pngs[newRel], hash);
});

// --- up: worker-count formula ------------------------------------------------

test('playwrightWorkers: min(4, floor(cores/2))', () => {
  assert.equal(playwrightWorkers(2), 1);
  assert.equal(playwrightWorkers(4), 2);
  assert.equal(playwrightWorkers(8), 4);
  assert.equal(playwrightWorkers(16), 4);
  assert.equal(playwrightWorkers(1), 1);
});

// --- Apple device setup (stage d): simulator name derivation ----------------

test('simulatorNameForDevice: deterministic per repo hash + device class', () => {
  assert.equal(simulatorNameForDevice('abcd1234', 'iphone'), 'screens-abcd1234-iphone');
});

test('repoHash: same root -> same hash; different roots -> different hashes', () => {
  const a = repoHash('/Users/rafael/Developer/apps/topf-secret/ios');
  const b = repoHash('/Users/rafael/Developer/apps/topf-secret/ios');
  const c = repoHash('/Users/rafael/Developer/apps/mail-guard');
  assert.equal(a, b);
  assert.notEqual(a, c);
});

// --- Apple device setup: disk guard branch -----------------------------------

test('parseDfAvailableGb: reads the Available column from `df -g` output', () => {
  const stdout = 'Filesystem     1G-blocks Used Available Capacity iused ifree %iused  Mounted on\n'
    + '/dev/disk3s1s1       460   12        26    33%  484014 275459240    0%   /\n';
  assert.equal(parseDfAvailableGb(stdout), 26);
});

test('checkDiskGuard: below 8 GB free -> not ok', () => {
  const runner = () => ({ stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 95 5 95%\n', status: 0 });
  const result = checkDiskGuard('/tmp', runner);
  assert.equal(result.ok, false);
  assert.equal(result.freeGb, 5);
});

test('checkDiskGuard: at or above 8 GB free -> ok', () => {
  const runner = () => ({ stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 80 20 80%\n', status: 0 });
  const result = checkDiskGuard('/tmp', runner);
  assert.equal(result.ok, true);
  assert.equal(result.freeGb, 20);
});

// --- Apple device setup: reuse of an existing simulator ----------------------

test('findSimulatorUdidByName: finds an existing device across runtime buckets', () => {
  const devicesJson = JSON.stringify({
    devices: {
      'com.apple.CoreSimulator.SimRuntime.iOS-18-0': [
        { name: 'screens-abcd1234-iphone', udid: 'UDID-1', state: 'Shutdown' },
      ],
    },
  });
  assert.equal(findSimulatorUdidByName(devicesJson, 'screens-abcd1234-iphone'), 'UDID-1');
  assert.equal(findSimulatorUdidByName(devicesJson, 'nonexistent'), null);
});

test('iosDeviceSetup: reuses an existing device, never calls simctl create', () => {
  const root = fixture();
  const config = { ios: { device_class: 'iphone' } };
  const name = simulatorNameForDevice(repoHash(root), 'iphone');
  let createCalled = false;
  const runner = (cmd, args) => {
    if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
    if (args[1] === 'list' && args[2] === 'devices') {
      return { stdout: JSON.stringify({ devices: { 'iOS-18': [{ name, udid: 'UDID-EXISTING' }] } }), status: 0 };
    }
    if (args[1] === 'create') createCalled = true;
    return { stdout: '', status: 0 };
  };
  const result = iosDeviceSetup(root, config, runner);
  assert.equal(result.ok, true);
  assert.equal(result.skip, false);
  assert.equal(result.udid, 'UDID-EXISTING');
  assert.equal(createCalled, false);
});

test('iosDeviceSetup: no existing device -> creates one from the newest available iOS runtime', () => {
  const root = fixture();
  const config = { ios: { device_class: 'iphone' } };
  const runtimesJson = JSON.stringify({
    runtimes: [
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-17-0', version: '17.0', isAvailable: true },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-18-2', version: '18.2', isAvailable: true },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.watchOS-11-0', version: '11.0', isAvailable: true },
    ],
  });
  const calls = [];
  const runner = (cmd, args) => {
    calls.push([cmd, ...args]);
    if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
    if (args[1] === 'list' && args[2] === 'devices') return { stdout: JSON.stringify({ devices: {} }), status: 0 };
    if (args[1] === 'list' && args[2] === 'runtimes') return { stdout: runtimesJson, status: 0 };
    if (args[1] === 'create') return { stdout: 'UDID-NEW\n', status: 0 };
    return { stdout: '', status: 0 };
  };
  const result = iosDeviceSetup(root, config, runner);
  assert.equal(result.ok, true);
  assert.equal(result.udid, 'UDID-NEW');
  const createCall = calls.find((c) => c[2] === 'create');
  assert.ok(createCall, calls.map((c) => c.join(' ')).join('\n'));
  assert.equal(createCall[createCall.length - 1], 'com.apple.CoreSimulator.SimRuntime.iOS-18-2');
});

test('iosDeviceSetup: below disk threshold -> SKIP, no simctl calls', () => {
  const root = fixture();
  let simctlCalled = false;
  const runner = (cmd) => {
    if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 95 5 95%\n', status: 0 };
    simctlCalled = true;
    return { stdout: '', status: 0 };
  };
  const result = iosDeviceSetup(root, {}, runner);
  assert.equal(result.skip, true);
  assert.match(result.reason, /low disk: 5 GB free/);
  assert.equal(simctlCalled, false);
});

test('macosDeviceSetup: below disk threshold -> SKIP; above -> ok, no simulator', () => {
  const root = fixture();
  const lowRunner = () => ({ stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 95 5 95%\n', status: 0 });
  const okRunner = () => ({ stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 });
  assert.equal(macosDeviceSetup(root, lowRunner).skip, true);
  const ok = macosDeviceSetup(root, okRunner);
  assert.equal(ok.ok, true);
  assert.equal(ok.skip, false);
  assert.equal(ok.udid, undefined);
});

// --- Apple device setup: status-bar / appearance command composition --------

test('statusBarOverrideArgs: composes the fixed 9:41 override', () => {
  assert.deepEqual(statusBarOverrideArgs('UDID-1'), [
    'simctl', 'status_bar', 'UDID-1', 'override',
    '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100',
    '--cellularBars', '4', '--wifiBars', '3',
  ]);
});

test('appearanceArgs: composes light/dark appearance switch', () => {
  assert.deepEqual(appearanceArgs('UDID-1', 'dark'), ['simctl', 'ui', 'UDID-1', 'appearance', 'dark']);
  assert.deepEqual(appearanceArgs('UDID-1', 'light'), ['simctl', 'ui', 'UDID-1', 'appearance', 'light']);
});

test('findNewestIosRuntimeId: picks the highest dotted version among available iOS runtimes', () => {
  const json = JSON.stringify({
    runtimes: [
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-16-4', version: '16.4', isAvailable: true },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-26-0', version: '26.0', isAvailable: true },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-18-0', version: '18.0', isAvailable: false },
    ],
  });
  assert.equal(findNewestIosRuntimeId(json), 'com.apple.CoreSimulator.SimRuntime.iOS-26-0');
});

// --- up: seed-on-change (fingerprint unchanged + isolated DB exists -> SKIP) ---

test('up: seed fingerprint unchanged from last run -> SEED=SKIP (unchanged), seed command not run', () => {
  const root = fixture();
  writeFile(root, 'database/seeders/ScreensDemoSeeder.php', '<?php // v1');
  const config = {
    platforms: ['web'],
    web: {
      framework: 'laravel', isolated_db: 'app_screens', fixed_now: '2026-05-12T09:41:00+02:00',
      health_url: null, seed_command: 'php artisan migrate:fresh --seed', start_command: null,
    },
  };
  writeJson(join(root, '.screens/config.json'), config);
  const fingerprint = computeSeedFingerprint(root, config);
  writeJson(join(root, '.screens/state.json'), { seed_fingerprint: fingerprint });

  let seedCalls = 0;
  let dbShowCalls = 0;
  const stubRunner = (cmd, args, env) => {
    if (cmd === 'php' && args[0] === 'artisan' && args[1] === 'db:show') {
      dbShowCalls++;
      // First call carries the override env (isolated db); the guard's
      // second, no-override call resolves the real (distinct) dev db.
      const database = (env && env.DB_DATABASE) || (dbShowCalls === 1 ? 'app_screens' : 'app');
      return { stdout: JSON.stringify({ platform: { config: { driver: 'pgsql', database } } }), status: 0 };
    }
    if (cmd === 'sh' && args[1] && args[1].includes('migrate:fresh')) seedCalls++;
    return { stdout: '', status: 0 };
  };
  const lines = cmdUp([], root, stubRunner);
  assert.ok(lines.some((l) => l === 'SEED=SKIP (unchanged)'), lines.join('\n'));
  assert.equal(seedCalls, 0);
});

test('up: seed fingerprint changed -> reseeds and stores the new fingerprint', () => {
  const root = fixture();
  writeFile(root, 'database/seeders/ScreensDemoSeeder.php', '<?php // v1');
  const config = {
    platforms: ['web'],
    web: {
      framework: 'laravel', isolated_db: 'app_screens', fixed_now: '2026-05-12T09:41:00+02:00',
      health_url: null, seed_command: 'php artisan migrate:fresh --seed', start_command: null,
    },
  };
  writeJson(join(root, '.screens/config.json'), config);
  writeJson(join(root, '.screens/state.json'), { seed_fingerprint: 'stale-fingerprint' });

  let seedCalls = 0;
  let dbShowCalls = 0;
  const stubRunner = (cmd, args, env) => {
    if (cmd === 'php' && args[0] === 'artisan' && args[1] === 'db:show') {
      dbShowCalls++;
      // First call carries the override env (isolated db); the guard's
      // second, no-override call resolves the real (distinct) dev db.
      const database = (env && env.DB_DATABASE) || (dbShowCalls === 1 ? 'app_screens' : 'app');
      return { stdout: JSON.stringify({ platform: { config: { driver: 'pgsql', database } } }), status: 0 };
    }
    if (cmd === 'sh' && args[1] && args[1].includes('migrate:fresh')) seedCalls++;
    return { stdout: '', status: 0 };
  };
  const lines = cmdUp([], root, stubRunner);
  assert.ok(lines.some((l) => l === 'SEED=OK'), lines.join('\n'));
  assert.equal(seedCalls, 1);
  const state = readJson(join(root, '.screens/state.json'), {});
  assert.equal(state.seed_fingerprint, computeSeedFingerprint(root, config));
});

test('up: --full forces reseed even when the fingerprint is unchanged', () => {
  const root = fixture();
  writeFile(root, 'database/seeders/ScreensDemoSeeder.php', '<?php // v1');
  const config = {
    platforms: ['web'],
    web: {
      framework: 'laravel', isolated_db: 'app_screens', fixed_now: '2026-05-12T09:41:00+02:00',
      health_url: null, seed_command: 'php artisan migrate:fresh --seed', start_command: null,
    },
  };
  writeJson(join(root, '.screens/config.json'), config);
  const fingerprint = computeSeedFingerprint(root, config);
  writeJson(join(root, '.screens/state.json'), { seed_fingerprint: fingerprint });

  let seedCalls = 0;
  let dbShowCalls = 0;
  const stubRunner = (cmd, args, env) => {
    if (cmd === 'php' && args[0] === 'artisan' && args[1] === 'db:show') {
      dbShowCalls++;
      // First call carries the override env (isolated db); the guard's
      // second, no-override call resolves the real (distinct) dev db.
      const database = (env && env.DB_DATABASE) || (dbShowCalls === 1 ? 'app_screens' : 'app');
      return { stdout: JSON.stringify({ platform: { config: { driver: 'pgsql', database } } }), status: 0 };
    }
    if (cmd === 'sh' && args[1] && args[1].includes('migrate:fresh')) seedCalls++;
    return { stdout: '', status: 0 };
  };
  const lines = cmdUp(['--full'], root, stubRunner);
  assert.ok(lines.some((l) => l === 'SEED=OK'), lines.join('\n'));
  assert.equal(seedCalls, 1);
});

// --- laravelPerfEnv: PHP_CLI_SERVER_WORKERS + APP_DEBUG=false on laravel ----

test('laravelPerfEnv: laravel framework -> PHP_CLI_SERVER_WORKERS=4, APP_DEBUG=false', () => {
  assert.deepEqual(laravelPerfEnv({ framework: 'laravel' }), { PHP_CLI_SERVER_WORKERS: '4', APP_DEBUG: 'false' });
});

test('laravelPerfEnv: non-laravel framework -> {} (inert)', () => {
  assert.deepEqual(laravelPerfEnv({ framework: 'astro' }), {});
});

// --- up: lock present -> FAIL ----------------------------------------------

test('up: lock present -> FAIL', () => {
  const root = fixture();
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], web: { framework: 'astro' } });
  writeFile(root, '.screens/.lock', 'pid');
  const lines = cmdUp([], root, () => {
    throw new Error('runner must not be called when locked');
  });
  assert.ok(lines.some((l) => l.startsWith('UP_RESULT=FAIL') && l.includes('locked')));
});

test('checkLock reflects the lock file directly', () => {
  const root = fixture();
  assert.equal(checkLock(root), false);
  writeFile(root, '.screens/.lock', 'pid');
  assert.equal(checkLock(root), true);
});

// --- checkLock: stale lock (dead PID) -> not locked, removed ---------------

test('checkLock: lock file with a dead PID -> not locked, stale lock removed', () => {
  const root = fixture();
  // spawnSync is synchronous: by the time it returns, the child has already
  // exited, so its pid is guaranteed dead for the rest of this test.
  const dead = spawnSync(process.execPath, ['-e', '0']);
  writeFile(root, '.screens/.lock', String(dead.pid));
  assert.equal(checkLock(root), false);
  assert.equal(existsSync(join(root, '.screens/.lock')), false);
});

// --- checkLock: lock file with the current (alive) PID -> FAIL (locked) ----

test('checkLock: lock file with the current process PID -> locked', () => {
  const root = fixture();
  writeFile(root, '.screens/.lock', String(process.pid));
  assert.equal(checkLock(root), true);
});

// --- Laravel guard: config cache present -> FAIL ----------------------------

test('laravelDbGuard: config cache present -> FAIL, runner never called', () => {
  const root = fixture();
  writeFile(root, 'bootstrap/cache/config.php', '<?php return [];');
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const guard = laravelDbGuard(root, config, () => {
    throw new Error('runner must not be called when config cache is present');
  });
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /config cache/);
});

// Real `php artisan db:show --json` output, captured from apps/zeit/app with
// DB_CONNECTION=sqlite DB_DATABASE=/tmp/screens-probe.sqlite: values nest
// under platform.config, not at the top level.
function dbShowOutput(driver, database) {
  return JSON.stringify({
    platform: { config: { driver, url: null, database, prefix: '' }, name: 'SQLite', connection: 'sqlite', version: '3.53.4', open_connections: null },
    tables: [],
  });
}

// --- Laravel guard: resolved DB path != isolated path -> FAIL --------------

test('laravelDbGuard: resolved DB path mismatch -> FAIL (stubbed db:show, real nested shape)', () => {
  const root = fixture();
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const stubRunner = () => ({ stdout: dbShowOutput('sqlite', '/real/app/database.sqlite'), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /does not match isolated path/);
});

test('laravelDbGuard: resolved DB path matches isolated path -> OK (real nested shape)', () => {
  const root = fixture();
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const stubRunner = () => ({ stdout: dbShowOutput('sqlite', join(root, '.screens/web/screens.sqlite')), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, true);
});

// --- Laravel guard: flat (wrong) shape -> FAIL ------------------------------

test('laravelDbGuard: flat-shape db:show output -> FAIL (real output nests under platform.config)', () => {
  const root = fixture();
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const flatShapeRunner = () => ({
    stdout: JSON.stringify({ driver: 'sqlite', database: join(root, '.screens/web/screens.sqlite') }),
    status: 0,
  });
  const guard = laravelDbGuard(root, config, flatShapeRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /platform\.config/);
});

// --- pgsql guard (revised 2026-09-24: zeit/events are Postgres-only) -------

function pgDbShowOutput(driver, database) {
  return JSON.stringify({
    platform: { config: { driver, url: null, database, prefix: '' }, name: 'PostgreSQL', connection: driver, version: '16.0', open_connections: null },
    tables: [],
  });
}

test('laravelDbGuard: pgsql isolated_db equals the dev database -> FAIL', () => {
  const root = fixture();
  const config = { web: { isolated_db: 'zeit_screens' } };
  // Both the overridden and the no-override db:show calls resolve to the
  // same database: the override never actually isolated anything.
  const stubRunner = () => ({ stdout: pgDbShowOutput('pgsql', 'zeit_screens'), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /equals the dev database/);
});

test('laravelDbGuard: pgsql isolated_db missing the _screens suffix -> FAIL', () => {
  const root = fixture();
  const config = { web: { isolated_db: 'zeit_isolated' } };
  let call = 0;
  // Dev db is distinct from the isolated one, so only the missing-suffix
  // check (not the equals-dev-db check) can produce this FAIL.
  const stubRunner = () => {
    call++;
    return { stdout: pgDbShowOutput('pgsql', call === 1 ? 'zeit_isolated' : 'zeit'), status: 0 };
  };
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /must end in _screens/);
});

test('laravelDbGuard: pgsql isolated_db valid and distinct from dev -> OK', () => {
  const root = fixture();
  const config = { web: { isolated_db: 'zeit_screens' } };
  let call = 0;
  const stubRunner = () => {
    call++;
    // First call carries the override env (isolated db); second call (dev
    // check) is invoked with an empty env and resolves the real dev db.
    if (call === 1) return { stdout: pgDbShowOutput('pgsql', 'zeit_screens'), status: 0 };
    return { stdout: pgDbShowOutput('pgsql', 'zeit'), status: 0 };
  };
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, true);
});

test('laravelDbGuard: unsupported driver (mysql) -> FAIL', () => {
  const root = fixture();
  const config = { web: { isolated_db: 'zeit_screens' } };
  const stubRunner = () => ({ stdout: pgDbShowOutput('mysql', 'zeit_screens'), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /unsupported database driver: mysql/);
});

// --- server-side fixed clock: PHP_INI_SCAN_DIR composition ----------------

test('composePhpIniScanDir: existing scan dir -> colon-joined with the additional dir', () => {
  // Real `php --ini` output quotes the path (verified against apps/zeit/app,
  // macOS Homebrew PHP 8.5): `Scan for additional .ini files in: "/opt/.../conf.d"`.
  const out = composePhpIniScanDir('Scan for additional .ini files in: "/opt/homebrew/etc/php/8.4/conf.d"\n', '/repo/.screens/web/php');
  assert.equal(out, '/opt/homebrew/etc/php/8.4/conf.d:/repo/.screens/web/php');
});

test('composePhpIniScanDir: "(none)" -> just the additional dir, no leading colon', () => {
  const out = composePhpIniScanDir('Scan for additional .ini files in: (none)\n', '/repo/.screens/web/php');
  assert.equal(out, '/repo/.screens/web/php');
});

test('phpFixedClockEnv: no fixed_now configured -> {} (inert), runner never called', () => {
  const root = fixture();
  const config = { web: { framework: 'laravel' } };
  const env = phpFixedClockEnv(root, config, () => {
    throw new Error('runner must not be called when fixed_now is unset');
  });
  assert.deepEqual(env, {});
});

test('phpFixedClockEnv: fixed_now configured on a laravel project -> PHP_INI_SCAN_DIR + SCREENS_FIXED_NOW', () => {
  const root = fixture();
  const config = { web: { framework: 'laravel', fixed_now: '2026-05-12T09:41:00+02:00' } };
  const stubRunner = () => ({ stdout: 'Scan for additional .ini files in: (none)\n', status: 0 });
  const env = phpFixedClockEnv(root, config, stubRunner);
  assert.equal(env.SCREENS_FIXED_NOW, '2026-05-12T09:41:00+02:00');
  assert.equal(env.PHP_INI_SCAN_DIR, join(root, '.screens/web/php'));
});

// --- trust: changed command hash -> NEEDS_CONFIRM --------------------------

test('trust: command hash differs from confirmed state -> NEEDS_CONFIRM', () => {
  const root = fixture();
  writeJson(join(root, '.screens/config.json'), { web: { start_command: 'php artisan serve' } });
  writeJson(join(root, '.screens/state.json'), { command_hash: 'stale-hash-from-before-the-edit' });
  const lines = cmdTrust([], root);
  assert.ok(lines.some((l) => l.startsWith('TRUST_RESULT=NEEDS_CONFIRM')));
});

test('trust: matching confirmed hash -> OK', () => {
  const root = fixture();
  const config = { web: { start_command: 'php artisan serve' } };
  writeJson(join(root, '.screens/config.json'), config);
  writeJson(join(root, '.screens/state.json'), { command_hash: computeCommandHash(config) });
  const lines = cmdTrust([], root);
  assert.ok(lines.some((l) => l === 'TRUST_RESULT=OK'));
});

// --- marketing: unreviewed headline -> output under _draft -----------------

test('marketing: unreviewed headline routes to _draft', () => {
  const dir = marketingTargetDir('web', 'de', '1920x1080', false);
  assert.ok(dir.includes('_draft'));
});

test('marketing: reviewed headline does not route to _draft', () => {
  const dir = marketingTargetDir('web', 'de', '1920x1080', true);
  assert.ok(!dir.includes('_draft'));
});

// --- marketing: rendering routing + change detection (renderer injected) ---

function marketingFixture(root, { reviewed = false } = {}) {
  writeJson(join(root, '.screens/config.json'), {
    platforms: ['web'],
    global_sources: [],
    marketing: {
      entries: [{ id: 'dashboard', headlines: { de: { text: 'Alles im Blick', reviewed } } }],
      locales: ['de'],
      formats: { web: '1920x1080' },
    },
  });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'dashboard', platform: 'web', area: 'app', view: 'dashboard', sources: [] }],
  });
  const sourceRel = 'web/desktop/app/dashboard/filled__admin__light.png';
  writeFile(root, join('screenshots', sourceRel), 'catalog-bytes');
  writeJson(join(root, '.screens/state.json'), {
    entries: { dashboard: { pngs: { [sourceRel]: require_sha256('catalog-bytes') } } },
  });
  // A render-marketing.mjs must exist for the renderer's own "not
  // scaffolded" guard, even though the injected stub renderer never reads it.
  writeFile(root, '.screens/web/render-marketing.mjs', '// stub');
  return sourceRel;
}

test('marketing: new entry -> renderer invoked with the resolved job, state records the render', () => {
  const root = fixture();
  marketingFixture(root);
  const calls = [];
  const stubRenderer = (_root, jobs) => {
    calls.push(jobs);
    return { ok: true, rendered: jobs.map((j) => ({ id: j.id, locale: j.locale, format: j.format, ok: true })) };
  };

  const lines = cmdMarketing([], root, stubRenderer);

  assert.equal(calls.length, 1);
  assert.equal(calls[0][0].id, 'dashboard');
  assert.equal(calls[0][0].headline, 'Alles im Blick');
  assert.ok(lines.some((l) => l.startsWith('MARKETING_RENDER dashboard de 1920x1080 ->') && l.includes('_draft')), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('MARKETING_RESULT=OK rendered=1')), lines.join('\n'));

  const state = readJson(join(root, '.screens/state.json'), {});
  assert.ok(state.marketing['dashboard__de__1920x1080'], 'state.marketing must record the render');
});

test('marketing: unchanged source + headline -> renderer not called, reported as skip', () => {
  const root = fixture();
  const sourceRel = marketingFixture(root);
  const state = readJson(join(root, '.screens/state.json'), {});
  state.marketing = {
    'dashboard__de__1920x1080': {
      sourceHash: state.entries.dashboard.pngs[sourceRel],
      headlineText: 'Alles im Blick', reviewed: false,
      relPath: join('_marketing', '_draft', 'web', 'de', '1920x1080', '01-dashboard.png'),
    },
  };
  writeJson(join(root, '.screens/state.json'), state);
  const stubRenderer = () => { throw new Error('renderer must not be called for an unchanged entry'); };

  const lines = cmdMarketing([], root, stubRenderer);

  assert.ok(lines.some((l) => l === 'MARKETING_SKIP dashboard de 1920x1080 (unchanged)'), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('MARKETING_RESULT=OK rendered=0 skipped=1')), lines.join('\n'));
});

test('marketing: headline set to reviewed -> re-renders and moves out of _draft, old draft file removed', () => {
  const root = fixture();
  const sourceRel = marketingFixture(root, { reviewed: true });
  const state = readJson(join(root, '.screens/state.json'), {});
  const oldDraftRel = join('_marketing', '_draft', 'web', 'de', '1920x1080', '01-dashboard.png');
  writeFile(root, join('screenshots', oldDraftRel), 'old-draft-bytes');
  state.marketing = {
    'dashboard__de__1920x1080': {
      sourceHash: state.entries.dashboard.pngs[sourceRel],
      headlineText: 'Alles im Blick', reviewed: false, relPath: oldDraftRel,
    },
  };
  writeJson(join(root, '.screens/state.json'), state);
  const stubRenderer = (_root, jobs) => ({ ok: true, rendered: jobs.map((j) => ({ id: j.id, locale: j.locale, format: j.format, ok: true })) });

  const lines = cmdMarketing([], root, stubRenderer);

  assert.ok(lines.some((l) => l.startsWith('MARKETING_RENDER dashboard de 1920x1080 ->') && !l.includes('_draft')), lines.join('\n'));
  assert.ok(!existsSync(join(root, 'screenshots', oldDraftRel)), 'the stale _draft file must be removed on review-state flip');
});

// --- resolveMarketingBackground: DESIGN.md token source, neutral fallback --

test('resolveMarketingBackground: no DESIGN.md -> neutral fallback', () => {
  const root = fixture();
  assert.equal(resolveMarketingBackground(root), '#f5f5f7');
});

test('resolveMarketingBackground: DESIGN.md names a token file with a background color', () => {
  const root = fixture();
  writeFile(root, 'DESIGN.md', 'Token source: resources/css/tokens.css');
  writeFile(root, 'resources/css/tokens.css', ':root { --color-background: #1a2b3c; }');
  assert.equal(resolveMarketingBackground(root), '#1a2b3c');
});

// --- parsePromotedFilename / buildIndexItems / buildIndexMarketing ---------

test('parsePromotedFilename: state__role__theme[__locale].png', () => {
  assert.deepEqual(parsePromotedFilename('filled__admin__light.png'), { state: 'filled', role: 'admin', theme: 'light', locale: undefined });
  assert.deepEqual(parsePromotedFilename('filled__admin__light__de.png'), { state: 'filled', role: 'admin', theme: 'light', locale: 'de' });
});

test('buildIndexItems: every PNG in state.entries becomes one item with a screenshots/-relative path', () => {
  const manifest = { entries: [{ id: 'dashboard', platform: 'web', area: 'app', view: 'dashboard' }] };
  const state = {
    entries: {
      dashboard: {
        pngs: {
          'web/desktop/app/dashboard/filled__admin__light.png': 'hash1',
          'web/mobile/app/dashboard/empty__guest__dark.png': 'hash2',
        },
      },
    },
  };
  const items = buildIndexItems(manifest, state);
  assert.equal(items.length, 2);
  assert.ok(items.every((i) => !i.path.startsWith('/') && !i.path.startsWith('screenshots')));
  assert.ok(items.some((i) => i.state === 'filled' && i.role === 'admin' && i.theme === 'light' && i.deviceClass === 'desktop'));
  assert.ok(items.some((i) => i.state === 'empty' && i.role === 'guest' && i.theme === 'dark' && i.deviceClass === 'mobile'));
});

test('buildIndexMarketing: one item per state.marketing record, relative path only', () => {
  const state = {
    marketing: {
      'dashboard__de__1920x1080': { headlineText: 'Alles im Blick', reviewed: true, relPath: '_marketing/web/de/1920x1080/01-dashboard.png' },
    },
  };
  const items = buildIndexMarketing(state);
  assert.equal(items.length, 1);
  assert.equal(items[0].id, 'dashboard');
  assert.equal(items[0].locale, 'de');
  assert.equal(items[0].headline, 'Alles im Blick');
  assert.equal(items[0].path, '_marketing/web/de/1920x1080/01-dashboard.png');
});

// --- cmdIndex: screenshots/index.html embeds every PNG, relative paths only -

test('cmdIndex: writes screenshots/index.html whose embedded JSON lists every PNG in state, relative paths only', () => {
  const root = fixture();
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'dashboard', platform: 'web', area: 'app', view: 'dashboard' }],
  });
  writeJson(join(root, '.screens/state.json'), {
    entries: {
      dashboard: {
        pngs: {
          'web/desktop/app/dashboard/filled__admin__light.png': 'hash1',
          'web/mobile/app/dashboard/empty__guest__dark.png': 'hash2',
        },
      },
    },
    last_run: { new: 1, updated: 0, unchanged: 1, removed: 0, drift: 0, failed: 0, date: '2026-09-24', commit: 'abc123' },
  });

  const lines = cmdIndex([], root);

  assert.ok(lines.includes('INDEX_RESULT=OK path=screenshots/index.html'), lines.join('\n'));
  const html = readFileSync(join(root, 'screenshots/index.html'), 'utf8');
  const match = /<script id="screens-data" type="application\/json">([\s\S]*?)<\/script>/.exec(html);
  assert.ok(match, 'index.html must embed the screens-data JSON block');
  const data = JSON.parse(match[1]);
  assert.equal(data.items.length, 2);
  assert.ok(data.items.every((i) => !i.path.startsWith('/')));
  assert.equal(data.last_run.commit, 'abc123');
});

// --- affected: path in one entry's sources -> only that id -----------------

test('affected: a path matching one entry sources -> only that id', () => {
  const manifest = {
    entries: [
      { id: 'a', sources: ['resources/views/a.blade.php'] },
      { id: 'b', sources: ['resources/views/b.blade.php'] },
    ],
  };
  const config = { global_sources: [] };
  const ids = affectedIds(manifest, config, ['resources/views/a.blade.php']);
  assert.deepEqual(ids, ['a']);
});

// --- affected: global_sources path -> all ids -------------------------------

test('affected: a global_sources path -> all ids', () => {
  const manifest = {
    entries: [
      { id: 'a', sources: ['resources/views/a.blade.php'] },
      { id: 'b', sources: ['resources/views/b.blade.php'] },
    ],
  };
  const config = { global_sources: ['composer.lock'] };
  const ids = affectedIds(manifest, config, ['composer.lock']);
  assert.deepEqual(ids, ['a', 'b']);
});

// --- affected: unrelated path -> none ---------------------------------------

test('affected: an unrelated path -> no ids', () => {
  const manifest = {
    entries: [
      { id: 'a', sources: ['resources/views/a.blade.php'] },
      { id: 'b', sources: ['resources/views/b.blade.php'] },
    ],
  };
  const config = { global_sources: ['composer.lock'] };
  const ids = affectedIds(manifest, config, ['README.md']);
  assert.deepEqual(ids, []);
});

// --- small local helper, mirrors the sha256 hashing promoteFile uses -----
function require_sha256(content) {
  return createHash('sha256').update(content).digest('hex');
}

// =============================================================================
// Android device setup (Maestro, stage e)
// =============================================================================

// --- AVD name derivation ------------------------------------------------

test('androidAvdName: deterministic per repo hash + device class, underscored', () => {
  assert.equal(androidAvdName('abcd1234', 'android-phone'), 'screens_abcd1234_android-phone');
  assert.equal(androidAvdName('abcd1234'), 'screens_abcd1234_android-phone');
});

// --- Emulator port derivation --------------------------------------------

test('androidEmulatorPort: even port in the 5554-5680 range, deterministic per hash', () => {
  const port = androidEmulatorPort('abcd1234');
  assert.ok(port >= 5554 && port <= 5680);
  assert.equal(port % 2, 0);
  assert.equal(androidEmulatorPort('abcd1234'), port);
});

test('androidEmulatorPort: different hashes usually give different ports', () => {
  assert.notEqual(androidEmulatorPort('11110000'), androidEmulatorPort('ffffaaaa'));
});

// --- SDK resolution -------------------------------------------------------

test('resolveAndroidSdkRoot: ANDROID_HOME wins when set', () => {
  assert.equal(resolveAndroidSdkRoot({ ANDROID_HOME: '/opt/android-home' }, '/Users/x'), '/opt/android-home');
});

test('resolveAndroidSdkRoot: falls back to ANDROID_SDK_ROOT, then ~/Library/Android/sdk', () => {
  assert.equal(resolveAndroidSdkRoot({ ANDROID_SDK_ROOT: '/opt/android-sdk-root' }, '/Users/x'), '/opt/android-sdk-root');
  assert.equal(resolveAndroidSdkRoot({}, '/Users/x'), '/Users/x/Library/Android/sdk');
});

test('androidToolPaths: composes adb/emulator/avdmanager under the resolved SDK root', () => {
  const tools = androidToolPaths('/sdk');
  assert.equal(tools.adb, join('/sdk', 'platform-tools', 'adb'));
  assert.equal(tools.emulator, join('/sdk', 'emulator', 'emulator'));
  assert.equal(tools.avdmanager, join('/sdk', 'cmdline-tools', 'latest', 'bin', 'avdmanager'));
});

// --- Preflight (each branch inverted goes red) ----------------------------

test('androidToolsPreflight: reports the first missing tool, in order', () => {
  const all = { maestro: true, java: true, emulator: true, adb: true, avdmanager: true };
  assert.equal(androidToolsPreflight({ ...all, maestro: false }).ok, false);
  assert.match(androidToolsPreflight({ ...all, maestro: false }).reason, /maestro not found/);
  assert.match(androidToolsPreflight({ ...all, java: false }).reason, /java not found/);
  assert.match(androidToolsPreflight({ ...all, emulator: false }).reason, /emulator not found/);
  assert.match(androidToolsPreflight({ ...all, adb: false }).reason, /adb not found/);
  assert.match(androidToolsPreflight({ ...all, avdmanager: false }).reason, /avdmanager not found/);
  assert.equal(androidToolsPreflight(all).ok, true);
});

// --- AVD reuse -------------------------------------------------------------

test('avdExists: exact match against a plain `avdmanager list avd -c` line list', () => {
  const output = 'events_repro\nscreens_abcd1234_android-phone\n';
  assert.equal(avdExists(output, 'screens_abcd1234_android-phone'), true);
  assert.equal(avdExists(output, 'events_repro'), true);
  assert.equal(avdExists(output, 'nonexistent'), false);
  assert.equal(avdExists('', 'nonexistent'), false);
});

// --- Installed system images (real fs walk over a fixture tree) -----------

test('findInstalledSystemImages: scans <sdk>/system-images/<api>/<tag>/<abi>, newest API first', () => {
  const root = fixture();
  mkdirSync(join(root, 'system-images/android-34/google_apis_playstore/arm64-v8a'), { recursive: true });
  mkdirSync(join(root, 'system-images/android-37/google_apis_playstore_ps16k/arm64-v8a'), { recursive: true });
  const images = findInstalledSystemImages(root);
  assert.deepEqual(images, [
    'system-images;android-37;google_apis_playstore_ps16k;arm64-v8a',
    'system-images;android-34;google_apis_playstore;arm64-v8a',
  ]);
});

test('findInstalledSystemImages: no system-images dir -> empty array, no throw', () => {
  const root = fixture();
  assert.deepEqual(findInstalledSystemImages(root), []);
});

// --- AVD create command composition ----------------------------------------

test('androidAvdCreateShellCmd: pipes "no" past the custom-hardware-profile prompt', () => {
  const cmd = androidAvdCreateShellCmd('/sdk/cmdline-tools/latest/bin/avdmanager', 'screens_abcd1234_android-phone', 'system-images;android-37;google_apis_playstore_ps16k;arm64-v8a');
  assert.equal(cmd, 'echo no | "/sdk/cmdline-tools/latest/bin/avdmanager" create avd -n "screens_abcd1234_android-phone" -k "system-images;android-37;google_apis_playstore_ps16k;arm64-v8a" -d "pixel_6"');
});

test('androidAvdCreateShellCmd: device profile override', () => {
  const cmd = androidAvdCreateShellCmd('/avdmanager', 'name', 'pkg', 'pixel_9');
  assert.match(cmd, /-d "pixel_9"/);
});

// --- Demo mode + theme command composition ----------------------------------

test('androidDemoModeArgs: sysui_demo_allowed first, then clock/battery/network/notifications broadcasts', () => {
  const calls = androidDemoModeArgs('emulator-5554');
  assert.deepEqual(calls[0], ['-s', 'emulator-5554', 'shell', 'settings', 'put', 'global', 'sysui_demo_allowed', '1']);
  assert.ok(calls.some((c) => c.includes('clock') && c.includes('0941')));
  assert.ok(calls.some((c) => c.includes('battery') && c.includes('100')));
  assert.ok(calls.some((c) => c.includes('network')));
  assert.ok(calls.some((c) => c.includes('notifications') && c.includes('false')));
});

test('androidThemeArgs: composes light/dark uimode night switch', () => {
  assert.deepEqual(androidThemeArgs('emulator-5554', 'dark'), ['-s', 'emulator-5554', 'shell', 'cmd', 'uimode', 'night', 'yes']);
  assert.deepEqual(androidThemeArgs('emulator-5554', 'light'), ['-s', 'emulator-5554', 'shell', 'cmd', 'uimode', 'night', 'no']);
});

// --- Boot wait ---------------------------------------------------------------

test('waitForAndroidBoot: sys.boot_completed=1 -> true immediately', () => {
  const runner = () => ({ stdout: '1\n', status: 0 });
  assert.equal(waitForAndroidBoot('/sdk/platform-tools/adb', 'emulator-5554', 5, runner), true);
});

test('waitForAndroidBoot: never reports 1 within the timeout -> false', () => {
  const runner = () => ({ stdout: '\n', status: 0 });
  assert.equal(waitForAndroidBoot('/sdk/platform-tools/adb', 'emulator-5554', 0, runner), false);
});

// --- androidDeviceSetup: full composition -----------------------------------

function androidFixtureSdk(root) {
  const sdkRoot = join(root, 'sdk');
  mkdirSync(join(sdkRoot, 'platform-tools'), { recursive: true });
  writeFileSync(join(sdkRoot, 'platform-tools/adb'), '');
  mkdirSync(join(sdkRoot, 'emulator'), { recursive: true });
  writeFileSync(join(sdkRoot, 'emulator/emulator'), '');
  mkdirSync(join(sdkRoot, 'cmdline-tools/latest/bin'), { recursive: true });
  writeFileSync(join(sdkRoot, 'cmdline-tools/latest/bin/avdmanager'), '');
  mkdirSync(join(sdkRoot, 'system-images/android-37/google_apis_playstore_ps16k/arm64-v8a'), { recursive: true });
  return sdkRoot;
}

const ALL_ANDROID_TOOLS = { maestro: true, java: true, emulator: true, adb: true, avdmanager: true };

test('androidDeviceSetup: reuses an existing AVD, never calls avdmanager create', () => {
  const root = fixture();
  androidFixtureSdk(root);
  process.env.ANDROID_HOME = join(root, 'sdk');
  try {
    const hash = repoHash(root);
    const name = androidAvdName(hash, 'android-phone');
    let createCalled = false;
    const runner = (cmd, args) => {
      if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
      if (Array.isArray(args) && args[0] === 'list') return { stdout: `${name}\n`, status: 0 };
      if (cmd === 'sh') createCalled = true;
      return { stdout: '', status: 0 };
    };
    const result = androidDeviceSetup(root, { android: {} }, runner, () => ALL_ANDROID_TOOLS);
    assert.equal(result.ok, true);
    assert.equal(result.skip, false);
    assert.equal(result.name, name);
    assert.equal(createCalled, false);
    assert.match(result.startCommand, /-no-window -no-audio -no-boot-anim -gpu swiftshader_indirect/);
  } finally {
    delete process.env.ANDROID_HOME;
  }
});

test('androidDeviceSetup: no existing AVD -> creates one from the newest installed system image', () => {
  const root = fixture();
  androidFixtureSdk(root);
  process.env.ANDROID_HOME = join(root, 'sdk');
  try {
    let createCmd = null;
    const runner = (cmd, args) => {
      if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
      if (Array.isArray(args) && args[0] === 'list') return { stdout: '', status: 0 };
      if (cmd === 'sh') {
        createCmd = args[1];
        return { stdout: '', status: 0 };
      }
      return { stdout: '', status: 0 };
    };
    const result = androidDeviceSetup(root, { android: {} }, runner, () => ALL_ANDROID_TOOLS);
    assert.equal(result.ok, true);
    assert.equal(result.skip, false);
    assert.match(createCmd, /system-images;android-37;google_apis_playstore_ps16k;arm64-v8a/);
  } finally {
    delete process.env.ANDROID_HOME;
  }
});

test('androidDeviceSetup: below disk threshold -> SKIP, no avdmanager calls', () => {
  const root = fixture();
  androidFixtureSdk(root);
  process.env.ANDROID_HOME = join(root, 'sdk');
  try {
    let avdmanagerCalled = false;
    const runner = (cmd) => {
      if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 95 5 95%\n', status: 0 };
      avdmanagerCalled = true;
      return { stdout: '', status: 0 };
    };
    const result = androidDeviceSetup(root, {}, runner, () => ALL_ANDROID_TOOLS);
    assert.equal(result.skip, true);
    assert.match(result.reason, /low disk: 5 GB free/);
    assert.equal(avdmanagerCalled, false);
  } finally {
    delete process.env.ANDROID_HOME;
  }
});

test('androidDeviceSetup: missing avdmanager -> SKIP with install hint, no create attempted', () => {
  const root = fixture();
  androidFixtureSdk(root);
  process.env.ANDROID_HOME = join(root, 'sdk');
  try {
    let createCalled = false;
    const runner = (cmd) => {
      if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
      if (cmd === 'sh') createCalled = true;
      return { stdout: '', status: 0 };
    };
    const result = androidDeviceSetup(root, {}, runner, () => ({ ...ALL_ANDROID_TOOLS, avdmanager: false }));
    assert.equal(result.skip, true);
    assert.match(result.reason, /avdmanager not found/);
    assert.equal(createCalled, false);
  } finally {
    delete process.env.ANDROID_HOME;
  }
});

test('androidDeviceSetup: no installed system image -> SKIP with the install command, never downloads', () => {
  const root = fixture();
  const sdkRoot = join(root, 'sdk');
  mkdirSync(join(sdkRoot, 'platform-tools'), { recursive: true });
  writeFileSync(join(sdkRoot, 'platform-tools/adb'), '');
  mkdirSync(join(sdkRoot, 'emulator'), { recursive: true });
  writeFileSync(join(sdkRoot, 'emulator/emulator'), '');
  mkdirSync(join(sdkRoot, 'cmdline-tools/latest/bin'), { recursive: true });
  writeFileSync(join(sdkRoot, 'cmdline-tools/latest/bin/avdmanager'), '');
  // no system-images written on purpose
  process.env.ANDROID_HOME = sdkRoot;
  try {
    const runner = (cmd, args) => {
      if (cmd === 'df') return { stdout: 'Filesystem 1G-blocks Used Available Capacity\n/dev/x 100 74 26 74%\n', status: 0 };
      if (Array.isArray(args) && args[0] === 'list') return { stdout: '', status: 0 };
      return { stdout: '', status: 0 };
    };
    const result = androidDeviceSetup(root, {}, runner, () => ALL_ANDROID_TOOLS);
    assert.equal(result.skip, true);
    assert.match(result.reason, /no Android system image installed/);
    assert.match(result.reason, /sdkmanager/);
  } finally {
    delete process.env.ANDROID_HOME;
  }
});
