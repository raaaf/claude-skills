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

import {
  planEntries,
  checkLock,
  cmdUp,
  laravelDbGuard,
  promoteFile,
  moveRemovedEntries,
  cmdTrust,
  computeCommandHash,
  marketingTargetDir,
  affectedIds,
  writeJson,
} from './screens.mjs';

function fixture() {
  return mkdtempSync(join(tmpdir(), 'screens-test-'));
}

function writeFile(root, relPath, content) {
  const full = join(root, relPath);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, content);
}

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
  const { changed } = promoteFile(join(root, 'incoming/entry__filled.png'), targetPath, prevHash);
  assert.equal(changed, true);
  assert.equal(readFileSync(targetPath, 'utf8'), 'new-bytes');
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

// --- Laravel guard: resolved DB path != isolated path -> FAIL --------------

test('laravelDbGuard: resolved DB path mismatch -> FAIL (stubbed db:show)', () => {
  const root = fixture();
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const stubRunner = () => ({ stdout: JSON.stringify({ driver: 'sqlite', database: '/real/app/database.sqlite' }), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, false);
  assert.match(guard.reason, /does not match isolated path/);
});

test('laravelDbGuard: resolved DB path matches isolated path -> OK', () => {
  const root = fixture();
  const config = { web: { isolated_db: '.screens/web/screens.sqlite' } };
  const stubRunner = () => ({ stdout: JSON.stringify({ driver: 'sqlite', database: join(root, '.screens/web/screens.sqlite') }), status: 0 });
  const guard = laravelDbGuard(root, config, stubRunner);
  assert.equal(guard.ok, true);
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
  const dir = marketingTargetDir('de', '1920x1080', false);
  assert.ok(dir.includes('_draft'));
});

test('marketing: reviewed headline does not route to _draft', () => {
  const dir = marketingTargetDir('de', '1920x1080', true);
  assert.ok(!dir.includes('_draft'));
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
