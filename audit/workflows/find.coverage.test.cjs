// Pins two coverage fixes in find.js (2026-10-02):
//   1. Path normalization: a cluster scout that returns absolute paths, or a specialist that
//      reports them, must not make hasCompleteCoverage mark one file both missing and extra.
//   2. Heavy-file split: under hunkScope a file with many/large hunk ranges gets its own chunk
//      (so one specialist handles just its hunks), SMALL and payments stay unchanged, and
//      coverage.reason reaches the "chunk N not covered" log line.
// architecture is CLUSTER_ONLY, so the cluster scout stub is the only scout.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workflowPath = path.join(__dirname, 'find.js');
const workflowSource = fs.readFileSync(workflowPath, 'utf8').replace(/^export const meta = /, 'const meta = ');
const ROOT = '/Users/x/Local Sites/repo';
const FILES = ['src/A.php', 'src/B.php', 'src/Big.php'];

function baseArgs(overrides) {
  return Object.assign({
    repoRoot: ROOT, scope: 'diff', files: FILES, dimensions: ['architecture'],
    promptDir: '/prompts', guidelinesDir: '/guidelines', floorFiles: {}, dimensionFiles: {}
  }, overrides);
}

const cluster = (paths) => ({
  clusters: [{ id: 'c1', pattern: 'p', why: 'w', files: paths.map((p) => ({ path: p, count: 1 })) }]
});

async function run(args, { clusters, audit }) {
  const logs = [];
  const specialistPrompts = [];
  const context = {
    args, log: (m) => logs.push(m), performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      if (options.phase === 'Scout') return clusters;
      if (options.phase === 'Audit') {
        const assigned = JSON.parse((prompt.match(/FILES=(\[.*?\])\n/) || prompt.match(/"files":(\[.*?\])\}/))[1]
          .replace(/\{"path":"([^"]*)","count":\d+\}/g, '"$1"'));
        specialistPrompts.push(assigned);
        return audit(assigned);
      }
      return { verdicts: [] };
    }
  };
  const result = await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  return { result, logs, specialistPrompts };
}

const complete = (assigned) => ({ findings: [], coverage: { status: 'complete', files: assigned } });
const heavy = Array.from({ length: 12 }, (_, i) => [i * 100 + 1, i * 100 + 40]);

test('absolute cluster paths are normalized, so a relative specialist reply covers them', async () => {
  const { result, logs } = await run(baseArgs(), {
    clusters: cluster([`${ROOT}/src/A.php`, `./src/B.php`]),
    audit: (assigned) => complete(assigned)
  });
  assert.equal(result.dimensions.architecture.status, 'complete');
  assert.ok(!logs.some((l) => l.includes('not covered')), logs.join('\n'));
});

test('a specialist replying with absolute paths still covers relative assignments', async () => {
  const { result } = await run(baseArgs(), {
    clusters: cluster(['src/A.php', 'src/B.php']),
    audit: (assigned) => complete(assigned.map((p) => `${ROOT}/${p}`))
  });
  assert.equal(result.dimensions.architecture.status, 'complete');
});

test('hunkScope: a heavy file leaves its cluster and gets its own chunk', async () => {
  const hunks = { 'src/A.php': [[1, 30]], 'src/B.php': [[1, 30]], 'src/Big.php': heavy };
  const { result, specialistPrompts, logs } = await run(
    baseArgs({ hunkScope: true, baseRef: 'main', sizeResult: 'LARGE', hunks }),
    { clusters: cluster(FILES), audit: complete });
  assert.equal(result.dimensions.architecture.chunks, 2);
  assert.deepEqual(specialistPrompts.map((p) => p.slice().sort()), [['src/A.php', 'src/B.php'], ['src/Big.php']]);
  assert.equal(result.dimensions.architecture.status, 'complete');
  assert.ok(logs.some((l) => l.includes('heavy-file split')));
});

test('a heavy file by line count alone (few ranges) is split too', async () => {
  const hunks = { 'src/A.php': [[1, 30]], 'src/B.php': [[1, 30]], 'src/Big.php': [[1, 500], [900, 1400]] };
  const { result } = await run(baseArgs({ hunkScope: true, baseRef: 'main', sizeResult: 'LARGE', hunks }),
    { clusters: cluster(FILES), audit: complete });
  assert.equal(result.dimensions.architecture.chunks, 2);
});

test('SMALL diff: chunk count unchanged even with heavy ranges', async () => {
  const hunks = { 'src/A.php': [[1, 30]], 'src/B.php': [[1, 30]], 'src/Big.php': heavy };
  const { result } = await run(baseArgs({ hunkScope: true, baseRef: 'main', sizeResult: 'SMALL', hunks }),
    { clusters: cluster(FILES), audit: complete });
  assert.equal(result.dimensions.architecture.chunks, 1);
});

test('hunkScope off: no split', async () => {
  const hunks = { 'src/Big.php': heavy };
  const { result } = await run(baseArgs({ hunks }), { clusters: cluster(FILES), audit: complete });
  assert.equal(result.dimensions.architecture.chunks, 1);
});

test('coverage.reason is passed through to the "not covered" log line', async () => {
  const { result, logs } = await run(baseArgs(), {
    clusters: cluster(['src/A.php', 'src/B.php']),
    audit: () => ({ findings: [], coverage: { status: 'incomplete', files: ['src/A.php'], reason: 'ran out of context in B.php' } })
  });
  assert.equal(result.dimensions.architecture.status, 'incomplete');
  assert.ok(logs.some((l) => l.includes('chunk 0 not covered') && l.includes('reason=ran out of context in B.php')), logs.join('\n'));
});
