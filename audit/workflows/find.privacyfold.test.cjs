// Pins the privacy fold (2026-10-01): with security AND privacy selected, privacy gets no scout,
// specialist or verifier of its own; the security specialist is told to read the privacy module
// and may tag findings `privacy`. Privacy alone still runs its own pipeline. The folded privacy
// is reported as status 'folded' (not skipped/incomplete) so the Phase 4 marker gate ignores it,
// and its floor files join security's scout floor.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workflowPath = path.join(__dirname, 'find.js');
const workflowSource = fs.readFileSync(workflowPath, 'utf8').replace(/^export const meta = /, 'const meta = ');

function baseArgs(overrides) {
  return Object.assign({
    repoRoot: '/repo', scope: 'repo', files: ['src/a.ts', 'src/consent.ts'],
    dimensions: ['security', 'privacy'],
    promptDir: '/prompts', guidelinesDir: '/guidelines',
    floorFiles: { security: ['src/a.ts'], privacy: ['src/consent.ts'] }
  }, overrides);
}

async function runWorkflow(args) {
  const prompts = [];
  const context = {
    args, log() {}, performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      prompts.push({ prompt, options });
      if (options.phase === 'Scout') {
        if (prompt.includes('cluster-scout')) return { clusters: [] };
        const floor = JSON.parse(prompt.match(/FLOOR_FILES=(\[.*?\])\n/)[1]);
        return { files: floor.map((p) => ({ path: p, tag: 'floor', reason: 'floor' })) };
      }
      if (options.phase === 'Audit') {
        const assigned = JSON.parse(prompt.match(/FILES=(\[.*?\])\n/)[1]);
        const findings = prompt.includes('DIMENSION=security')
          ? [{ id: 'privacy-consent-1', severity: 'Important', confidence: 'high',
            files: [{ path: 'src/consent.ts', lines: '3' }], issue: 'script loads without consent', impact: 'x' }]
          : [];
        return { findings, coverage: { status: 'complete', files: assigned } };
      }
      const findings = JSON.parse(prompt.match(/FINDINGS=(\[.*\])/)[1]);
      return { verdicts: findings.map((f) => ({ id: f.id, verdict: 'CONFIRMED', severity: f.severity, reason: 'ok' })) };
    }
  };
  const result = await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  return { result, prompts };
}

test('security + privacy: privacy dispatches nothing, security reads the privacy module and the union floor', async () => {
  const { result, prompts } = await runWorkflow(baseArgs());
  assert.ok(!prompts.some((p) => p.prompt.includes('DIMENSION=privacy')));
  const specialists = prompts.filter((p) => p.options.phase === 'Audit');
  assert.ok(specialists.length > 0);
  for (const p of specialists) assert.ok(p.prompt.includes('/prompts/13-privacy.md'));
  const scout = prompts.find((p) => p.options.phase === 'Scout' && p.prompt.includes('DIMENSION=security'));
  assert.ok(scout.prompt.includes('src/consent.ts') && scout.prompt.includes('src/a.ts'));
  assert.deepEqual(
    { status: result.dimensions.privacy.status, into: result.dimensions.privacy.into },
    { status: 'folded', into: 'security' });
  assert.ok(!result.skipped.includes('privacy'));
  assert.equal(result.status, 'complete');
  // the privacy-tagged finding is verified by security's verifier and reported under security
  assert.equal(result.dimensions.security.findings[0].id, 'privacy-consent-1');
  assert.equal(result.dimensions.security.verdicts.length, 1);
});

test('privacy alone: own pipeline, no fold', async () => {
  const { result, prompts } = await runWorkflow(baseArgs({ dimensions: ['privacy'] }));
  assert.ok(prompts.some((p) => p.options.phase === 'Scout' && p.prompt.includes('DIMENSION=privacy')));
  const specialists = prompts.filter((p) => p.options.phase === 'Audit');
  assert.ok(specialists.length > 0);
  for (const p of specialists) assert.ok(p.prompt.includes('DIMENSION=privacy'));
  assert.notEqual(result.dimensions.privacy.status, 'folded');
  assert.ok(!prompts.some((p) => p.prompt.includes('PRIVACY FOLD')));
});
