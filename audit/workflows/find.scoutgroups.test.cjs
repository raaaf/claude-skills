// Pins grouped file scouting: dimensions that share an agent type and SCOPE_FILES share one
// Explore call (measured 2026-10-01: every audit agent starts at ~27k context, 40% of the
// scouts' weighted cost is startup). What must hold:
//   - one scout dispatch per group, each dimension's specialist gets its own slice;
//   - per-dimension post-processing (floor re-add) still applies to a slice;
//   - a null group reply or a dimension missing from it falls back to the single scout;
//   - payments with dimensionFiles never joins a group.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workflowPath = path.join(__dirname, 'find.js');
const workflowSource = fs.readFileSync(workflowPath, 'utf8').replace(/^export const meta = /, 'const meta = ');

const FILES = ['a.ts', 'b.ts', 'c.ts', 'd.ts', 'e.ts', 'f.ts'];

function baseArgs(overrides) {
  return Object.assign({
    repoRoot: '/repo', scope: 'repo', files: FILES,
    dimensions: ['a11y', 'typography', 'ux', 'code_quality', 'copy', 'performance'],
    promptDir: '/prompts', guidelinesDir: '/guidelines',
    floorFiles: {}, dimensionFiles: {}
  }, overrides);
}

// Each dimension's own file, so a slice is recognisable in its specialist prompt.
const ownFile = (dimension) => `${dimension}.ts`;

async function runWorkflow(args, { groupReply, singleReply } = {}) {
  const prompts = [];
  const context = {
    args, log() {}, performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      prompts.push({ prompt, options });
      if (options.phase === 'Scout') {
        const group = prompt.match(/DIMENSIONS=(\[.*\])\n/);
        if (group) {
          const dims = JSON.parse(group[1]).map((entry) => entry.dimension);
          const reply = { dimensions: dims.map((dimension) => ({ dimension, files: [{ path: ownFile(dimension), tag: 'scope', reason: 'trigger' }] })) };
          return groupReply ? groupReply(reply, dims) : reply;
        }
        const dimension = prompt.match(/DIMENSION=(\w+)/)[1];
        const reply = { files: [{ path: ownFile(dimension), tag: 'scope', reason: 'single' }] };
        return singleReply ? singleReply(reply, dimension) : reply;
      }
      if (options.phase === 'Audit') {
        const filesMatch = prompt.match(/FILES=(\[.*?\])\n/);
        const assigned = filesMatch ? JSON.parse(filesMatch[1]) : [];
        return { findings: [], coverage: { status: 'complete', files: assigned } };
      }
      return { verdicts: [] };
    }
  };
  const result = await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  return { result, prompts, scouts: prompts.filter((p) => p.options.phase === 'Scout') };
}

const specialistFor = (prompts, dimension) =>
  prompts.find((p) => p.options.phase === 'Audit' && p.prompt.includes(`DIMENSION=${dimension}.`));

test('6 dimensions over 3 agent types dispatch 3 scouts and each specialist gets its own slice', async () => {
  const { result, prompts, scouts } = await runWorkflow(baseArgs());
  assert.equal(scouts.length, 3);
  assert.equal(scouts.filter((s) => s.prompt.includes('DIMENSIONS=')).length, 2);
  assert.equal(scouts.filter((s) => s.prompt.includes('DIMENSION=performance')).length, 1);
  for (const dimension of ['a11y', 'typography', 'ux', 'code_quality', 'copy', 'performance']) {
    const specialist = specialistFor(prompts, dimension);
    assert.ok(specialist.prompt.includes(`FILES=["${ownFile(dimension)}"]`), dimension);
    assert.deepEqual(result.dimensions[dimension].files, [ownFile(dimension)]);
    assert.equal(result.dimensions[dimension].status, 'complete');
  }
});

test('a floor file missing from the group reply is re-added for that dimension only', async () => {
  const { result } = await runWorkflow(
    baseArgs({ dimensions: ['a11y', 'typography'], floorFiles: { a11y: ['a.ts'], typography: [] } })
  );
  assert.deepEqual(result.dimensions.a11y.files.sort(), ['a.ts', 'a11y.ts']);
  assert.deepEqual(result.dimensions.typography.files, ['typography.ts']);
});

test('a null group reply makes every grouped dimension fall back to its single scout', async () => {
  const { result, scouts } = await runWorkflow(
    baseArgs({ dimensions: ['a11y', 'typography', 'ux'] }), { groupReply: () => null }
  );
  assert.equal(scouts.length, 1 + 3);
  for (const dimension of ['a11y', 'typography', 'ux']) {
    assert.deepEqual(result.dimensions[dimension].files, [ownFile(dimension)]);
    assert.equal(result.dimensions[dimension].status, 'complete');
  }
});

test('a dimension missing from the group reply is the only one that falls back', async () => {
  const { result, scouts } = await runWorkflow(
    baseArgs({ dimensions: ['a11y', 'typography', 'ux'] }),
    { groupReply: (reply) => ({ dimensions: reply.dimensions.filter((e) => e.dimension !== 'ux') }) }
  );
  assert.equal(scouts.length, 2);
  assert.ok(scouts[1].prompt.includes('DIMENSION=ux'));
  assert.equal(result.dimensions.ux.files[0], 'ux.ts');
  assert.equal(result.dimensions.a11y.status, 'complete');
});

test('payments with dimensionFiles keeps its own scout even next to security', async () => {
  const { scouts } = await runWorkflow(
    baseArgs({ dimensions: ['security', 'privacy', 'payments'], dimensionFiles: { payments: ['f.ts'] } })
  );
  const payments = scouts.filter((s) => s.prompt.includes('DIMENSION=payments'));
  assert.equal(payments.length, 1);
  assert.ok(payments[0].prompt.includes('SCOPE_FILES=["f.ts"]'));
  assert.ok(!scouts.some((s) => s.prompt.includes('DIMENSIONS=') && s.prompt.includes('payments')));
});
