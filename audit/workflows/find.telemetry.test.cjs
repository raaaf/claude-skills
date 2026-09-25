const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workflowPath = path.join(__dirname, 'find.js');
const workflowSource = fs.readFileSync(workflowPath, 'utf8').replace(/^export const meta = /, 'const meta = ');

async function runWorkflow(mode, withClock = true) {
  let tick = 0;
  const args = {
    repoRoot: '/repo', scope: 'repo', files: ['src/model.ts'], dimensions: ['architecture'],
    promptDir: '/prompts', guidelinesDir: '/guidelines', floorFiles: { architecture: [] }
  };
  const context = {
    args,
    log() {},
    performance: withClock ? { now: () => (tick += 8) } : undefined,
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      if (options.phase === 'Scout') {
        return { clusters: mode === 'skipped' ? [] : [{
          id: 'cluster-1', pattern: 'model consistency',
          files: [{ path: 'src/model.ts', count: 1 }, { path: 'src/related.ts', count: 1 }], why: 'related models'
        }] };
      }
      if (options.phase === 'Audit') {
        const cluster = JSON.parse(prompt.match(/CLUSTER=(\{.*\})/)[1]);
        const assigned = cluster.files.map((file) => file.path);
        if (mode === 'incomplete') return { findings: [], coverage: { status: 'incomplete', files: [] } };
        return {
          findings: [{ id: 'architecture-0-1', severity: 'Critical', confidence: 'high',
            files: [{ path: assigned[0], lines: '12' }], issue: 'unsafe invariant', impact: 'data corruption' }],
          coverage: { status: 'complete', files: assigned }
        };
      }
      if (prompt.includes('Try to refute')) {
        const finding = JSON.parse(prompt.match(/FINDING=(\{.*\})\nVERDICT=/)[1]);
        return { verdicts: [{ id: finding.id, verdict: 'REFUTED', severity: 'Critical', reason: 'not reproducible' }] };
      }
      const findings = JSON.parse(prompt.match(/FINDINGS=(\[.*\])/)[1]);
      return { verdicts: findings.map((finding) => ({ id: finding.id, verdict: 'CONFIRMED', severity: finding.severity, reason: 'reproduced' })) };
    }
  };
  return vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
}

test('complete dimensions expose phase dispatches and elapsed time without affecting gate status', async () => {
  const measured = await runWorkflow('complete', true);
  const unmeasured = await runWorkflow('complete', false);
  const dimension = measured.dimensions.architecture;
  assert.equal(dimension.status, 'complete');
  assert.equal(unmeasured.dimensions.architecture.status, dimension.status);
  assert.equal(dimension.telemetry.stages.scout.dispatches, 1);
  assert.equal(dimension.telemetry.stages.specialist.dispatches, 1);
  assert.equal(dimension.telemetry.stages.verifier.dispatches, 1);
  assert.equal(dimension.telemetry.stages.refuter.dispatches, 1);
  for (const item of [dimension.telemetry, ...Object.values(dimension.telemetry.stages)]) {
    assert.equal(typeof item.durationMs, 'number');
    assert.ok(item.durationMs >= 0);
  }
});

test('skipped and incomplete dimensions include truthful telemetry and preserve status', async () => {
  const skipped = await runWorkflow('skipped');
  const skippedWithoutClock = await runWorkflow('skipped', false);
  assert.equal(skipped.dimensions.architecture.status, 'skipped');
  assert.equal(skippedWithoutClock.dimensions.architecture.status, 'skipped');
  const skippedTelemetry = skipped.dimensions.architecture.telemetry;
  assert.equal(skippedTelemetry.stages.scout.dispatches, 1);
  assert.equal(skippedTelemetry.stages.specialist.dispatches, 0);
  assert.equal(skippedTelemetry.stages.specialist.durationMs, null);

  const incomplete = await runWorkflow('incomplete');
  const incompleteWithoutClock = await runWorkflow('incomplete', false);
  assert.equal(incomplete.dimensions.architecture.status, 'incomplete');
  assert.equal(incompleteWithoutClock.dimensions.architecture.status, 'incomplete');
  assert.equal(incomplete.dimensions.architecture.telemetry.stages.specialist.dispatches, 1);
  assert.equal(incomplete.dimensions.architecture.telemetry.stages.verifier.dispatches, 0);
  assert.equal(incomplete.dimensions.architecture.telemetry.stages.verifier.durationMs, null);
});
