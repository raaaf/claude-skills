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
  planEntries,
  checkLock,
  cmdUp,
  laravelDbGuard,
  composePhpIniScanDir,
  phpFixedClockEnv,
  promoteFile,
  moveRemovedEntries,
  cmdPromote,
  cmdPlan,
  cmdTrust,
  computeCommandHash,
  marketingTargetDir,
  affectedIds,
  writeJson,
  readJson,
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

// --- promote persists the fingerprint plan needs on the next run ---------

test('promote: persists entry fingerprint so a later plan call with no source changes reports unchanged', () => {
  const root = fixture();
  writeFile(root, 'view.blade.php', 'a');
  writeJson(join(root, '.screens/config.json'), { platforms: ['web'], global_sources: [] });
  writeJson(join(root, '.screens/manifest.json'), {
    entries: [{ id: 'entry', platform: 'web', area: 'area', view: 'entry', sources: ['view.blade.php'] }],
  });
  writeJson(join(root, '.screens/state.json'), { entries: {} });
  writeFile(root, '.screens/.incoming/web/entry__filled.png', 'bytes');

  cmdPromote(['--platform', 'web'], root);

  const stateAfterPromote = readJson(join(root, '.screens/state.json'), {});
  assert.ok(stateAfterPromote.entries.entry.fingerprint, 'promote must store a fingerprint');

  const planLines = cmdPlan([], root);
  assert.ok(planLines.includes('PLAN_ENTRY entry unchanged'), planLines.join('\n'));
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
  writeFile(root, '.screens/.incoming/web/reorderable__filled.png', 'bytes');

  const lines = cmdPromote(['--platform', 'web'], root);

  assert.ok(lines.some((l) => l === 'PROMOTE_ENTRY reorderable known_nondeterministic (row order has no ORDER BY tie-break)'), lines.join('\n'));
  assert.ok(lines.some((l) => l.startsWith('PROMOTE_RESULT=OK changed=0 unchanged=0 removed=0 known_nondeterministic=1')), lines.join('\n'));
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
