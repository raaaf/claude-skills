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

function entryPngsExist(root, entryState) {
  if (!entryState || !entryState.dir || !entryState.pngs) return false;
  return Object.keys(entryState.pngs).some((f) => existsSync(join(root, 'screenshots', entryState.dir, f)));
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

// Simulator/AVD creation belongs to later delivery stages (Apple + Maestro
// drivers). This hook is the single place that reports that honestly
// instead of pretending a device got created.
function deviceSetupHook(platform) {
  if (platform === 'ios' || platform === 'android' || platform === 'macos') {
    return { ok: true, skip: true, reason: `${platform} device setup not implemented yet (added in a later stage)` };
  }
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

  const device = deviceSetupHook(platform);
  if (device.skip) {
    lines.push(`UP_RESULT=SKIP (${device.reason})`);
    return lines;
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

  if (platformConfig.start_command) {
    const child = spawn(platformConfig.start_command, {
      shell: true,
      cwd: root,
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, ...(platformConfig.env || {}) },
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

  if (platformConfig.seed_command) {
    const seedResult = runner('sh', ['-c', platformConfig.seed_command], platformConfig.env || {});
    if (seedResult.status !== 0) {
      lines.push('UP_RESULT=FAIL (seed command failed)');
      return lines;
    }
    lines.push('SEED=OK');
  }

  lines.push('UP_RESULT=OK');
  return lines;
}

function cmdDown(args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const platform = argValue(args, '--platform') || (config.platforms && config.platforms[0]);

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

// Byte-hash compare: unchanged content leaves the target file untouched
// (mtime included), changed content overwrites it. No pixel decoder (see
// plan's Approach: fixed clock + disabled animations + masks make an
// identical render produce identical PNG bytes from the same encoder).
function promoteFile(incomingPath, targetPath, prevHash) {
  const buf = readFileSync(incomingPath);
  const hash = createHash('sha256').update(buf).digest('hex');
  if (prevHash && hash === prevHash && existsSync(targetPath)) {
    return { changed: false, hash };
  }
  mkdirSync(dirname(targetPath), { recursive: true });
  writeFileSync(targetPath, buf);
  return { changed: true, hash };
}

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function moveRemovedEntries(root, manifestIds, state, dateStr = todayStr()) {
  const moved = [];
  for (const id of Object.keys(state.entries || {})) {
    if (manifestIds.includes(id)) continue;
    const dir = state.entries[id].dir;
    if (!dir) continue;
    const src = join(root, 'screenshots', dir);
    if (!existsSync(src)) continue;
    const dest = join(root, 'screenshots', '_removed', dateStr, dir);
    mkdirSync(dirname(dest), { recursive: true });
    renameSync(src, dest);
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

  const incomingDir = join(root, '.screens/.incoming', platform || '');
  let changed = 0;
  let unchanged = 0;
  if (existsSync(incomingDir)) {
    for (const file of readdirSync(incomingDir)) {
      if (!file.endsWith('.png') || !file.includes('__')) continue;
      const id = file.slice(0, file.indexOf('__'));
      const rest = file.slice(file.indexOf('__') + 2);
      const entry = manifest.entries.find((e) => e.id === id);
      if (!entry) continue;
      const targetDir = join(root, 'screenshots', entry.platform || platform, entry.area || 'misc', entry.view || entry.id);
      const targetPath = join(targetDir, rest);
      const relDir = relative(join(root, 'screenshots'), targetDir);
      const prevHash = state.entries[id] && state.entries[id].pngs && state.entries[id].pngs[rest];
      const { changed: didChange, hash } = promoteFile(join(incomingDir, file), targetPath, prevHash);
      state.entries[id] = state.entries[id] || { dir: relDir };
      state.entries[id].dir = relDir;
      state.entries[id].pngs = state.entries[id].pngs || {};
      state.entries[id].pngs[rest] = hash;
      // Persisted here (not just computed transiently in `plan`): without
      // this, `plan`'s `prev.fingerprint` is always undefined on the next
      // run, and every entry reports `stale` forever even with zero source
      // changes (Step 6's `run 2 -> new=0 updated=0` requirement).
      state.entries[id].fingerprint = computeFingerprint(root, entry.sources || [], config.global_sources || []);
      if (didChange) changed++;
      else unchanged++;
      lines.push(`PROMOTE_ENTRY ${id} ${didChange ? 'changed' : 'unchanged'}`);
    }
  }

  const manifestIds = manifest.entries.map((e) => e.id);
  const removed = moveRemovedEntries(root, manifestIds, state);
  for (const id of removed) lines.push(`PROMOTE_REMOVED ${id}`);

  writeJson(join(root, '.screens/state.json'), state);
  lines.push(`PROMOTE_RESULT=OK changed=${changed} unchanged=${unchanged} removed=${removed.length}`);
  return lines;
}

// ---------------------------------------------------------------------
// marketing / index: decision logic only in this stage; the Playwright
// renderer is added in stage (c) (plan step 7).
// ---------------------------------------------------------------------

// Review gate: an unreviewed headline routes its render to `_draft`
// instead of the real marketing output (plan's "Marketing" section).
function marketingTargetDir(locale, format, reviewed) {
  return reviewed ? join('_marketing', locale, format) : join('_marketing', '_draft', locale, format);
}

// Change detection: only re-render when the source PNG hash or the
// headline text changed since the last render.
function marketingNeedsRender(prevRecord, sourceHash, headlineText) {
  if (!prevRecord) return true;
  return prevRecord.sourceHash !== sourceHash || prevRecord.headlineText !== headlineText;
}

// `_args` is unused today (no marketing flags yet, e.g. a future --platform
// filter) but kept, underscore-prefixed, so this stays call-compatible with
// main()'s uniform `handler(rest)` dispatch and with cmdIndex below.
function cmdMarketing(_args, root = process.cwd()) {
  const lines = [];
  const config = readJson(join(root, '.screens/config.json'), {});
  const entries = (config.marketing && config.marketing.entries) || [];
  const locales = (config.marketing && config.marketing.locales) || ['de'];
  let draftCount = 0;
  let readyCount = 0;
  for (const entry of entries) {
    for (const locale of locales) {
      const headline = entry.headlines && entry.headlines[locale];
      const reviewed = !!(headline && headline.reviewed);
      const dir = marketingTargetDir(locale, entry.format || 'default', reviewed);
      lines.push(`MARKETING_PLAN ${entry.id} ${locale} -> ${dir}`);
      if (reviewed) readyCount++;
      else draftCount++;
    }
  }
  lines.push(`MARKETING_RESULT=SKIP (renderer added in stage c; draft=${draftCount} ready=${readyCount})`);
  return lines;
}

// Both parameters are unused in this stage: the renderer (stage c) is what
// will actually read the manifest/state under `root` and accept args. Kept,
// underscore-prefixed, for the same call-compatibility reason as cmdMarketing.
function cmdIndex(_args, _root = process.cwd()) {
  return ['INDEX_RESULT=SKIP (renderer added in stage c)'];
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
  planEntries,
  cmdPlan,
  checkLock,
  deviceSetupHook,
  laravelDbGuard,
  bunDbGuard,
  cmdUp,
  cmdDown,
  promoteFile,
  moveRemovedEntries,
  cmdPromote,
  marketingTargetDir,
  marketingNeedsRender,
  cmdMarketing,
  cmdIndex,
  computeCommandHash,
  cmdTrust,
  affectedIds,
  cmdAffected,
  readJson,
  writeJson,
};
