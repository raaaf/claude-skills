// Pins hunkScope: on a LARGE/HUGE diff, SKILL.md Phase 2 passes hunkScope:true + baseRef so
// specialists stop reviewing whole files (learning-log 2026-09-25, events repo: three audits in
// a row reported mostly Important findings in untouched, pre-existing code of files the diff
// touched). What must hold:
//   - hunkScope:true without a non-empty baseRef throws before any agent is dispatched.
//   - with hunkScope, a specialist prompt carries the git-diff instruction and scope rule.
//   - payments never gets the clause: its scope is the full STRIPE_FILES surface, not the diff's
//     changed hunks (dimensionFiles is intentionally whole-file).
//   - the verifier prompt carries the clause too, so it can refute an out-of-scope finding.
//
// code_quality (not architecture) is used as the "ordinary" dimension: architecture is
// CLUSTER_ONLY, and stubbing a cluster scout is unrelated noise for what this test pins.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const workflowPath = path.join(__dirname, 'find.js');
const workflowSource = fs.readFileSync(workflowPath, 'utf8').replace(/^export const meta = /, 'const meta = ');

function baseArgs(overrides) {
  return Object.assign({
    repoRoot: '/repo', scope: 'repo', files: ['src/model.ts', 'app/Billing/Charge.php'],
    dimensions: ['code_quality', 'payments'],
    promptDir: '/prompts', guidelinesDir: '/guidelines',
    floorFiles: { code_quality: [], payments: [] },
    dimensionFiles: { payments: ['app/Billing/Charge.php'] }
  }, overrides);
}

function scoutFilesStub(prompt) {
  const path_ = prompt.includes('DIMENSION=payments') ? 'app/Billing/Charge.php' : 'src/model.ts';
  return { files: [{ path: path_, tag: 'floor', reason: 'floor' }] };
}

async function runWorkflow(args) {
  const prompts = [];
  const context = {
    args,
    log() {},
    performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      prompts.push({ prompt, options });
      if (options.phase === 'Scout') return scoutFilesStub(prompt);
      if (options.phase === 'Audit') {
        const filesMatch = prompt.match(/FILES=(\[.*?\])\n/);
        const assigned = filesMatch ? JSON.parse(filesMatch[1]) : [];
        return { findings: [], coverage: { status: 'complete', files: assigned } };
      }
      const findingsMatch = prompt.match(/FINDINGS=(\[.*\])/);
      const findings = findingsMatch ? JSON.parse(findingsMatch[1]) : [];
      return { verdicts: findings.map((finding) => ({ id: finding.id, verdict: 'CONFIRMED', severity: finding.severity, reason: 'reproduced' })) };
    }
  };
  const result = await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  return { result, prompts };
}

test('hunkScope:true without a non-empty baseRef throws', async () => {
  await assert.rejects(
    () => runWorkflow(baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true })),
    /args\.baseRef must be a non-empty string/
  );
  await assert.rejects(
    () => runWorkflow(baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true, baseRef: '' })),
    /args\.baseRef must be a non-empty string/
  );
});

test('hunkScope off: no specialist prompt carries the git-diff instruction', async () => {
  const { prompts } = await runWorkflow(baseArgs({ dimensions: ['code_quality'], dimensionFiles: {} }));
  const specialistPrompts = prompts.filter((p) => p.options.phase === 'Audit');
  assert.ok(specialistPrompts.length > 0);
  for (const p of specialistPrompts) assert.ok(!p.prompt.includes('HUNK SCOPE'));
});

test('hunkScope on: code_quality specialist prompt carries the git-diff instruction, payments does not', async () => {
  const { prompts } = await runWorkflow(baseArgs({ hunkScope: true, baseRef: 'origin/main' }));
  const specialistPrompts = prompts.filter((p) => p.options.phase === 'Audit');
  assert.ok(specialistPrompts.length > 0);

  const codeQualityPrompts = specialistPrompts.filter((p) => p.prompt.includes('DIMENSION=code_quality'));
  assert.ok(codeQualityPrompts.length > 0);
  for (const p of codeQualityPrompts) {
    assert.ok(p.prompt.includes('HUNK SCOPE'));
    assert.ok(p.prompt.includes('git -C REPO_ROOT diff origin/main -U15'));
  }

  const paymentsPrompts = specialistPrompts.filter((p) => p.prompt.includes('DIMENSION=payments'));
  assert.ok(paymentsPrompts.length > 0);
  for (const p of paymentsPrompts) assert.ok(!p.prompt.includes('HUNK SCOPE'));
});

test('hunkScope on: the verifier prompt carries the clause so it can refute an out-of-scope finding', async () => {
  const args = baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true, baseRef: 'origin/main' });
  let seenVerifierPrompt = null;
  const context = {
    args,
    log() {},
    performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      if (options.phase === 'Scout') return scoutFilesStub(prompt);
      if (options.phase === 'Audit') {
        return {
          findings: [{ id: 'code_quality-0-1', severity: 'Important', confidence: 'high',
            files: [{ path: 'src/model.ts', lines: '3' }], issue: 'pre-existing smell', impact: 'none' }],
          coverage: { status: 'complete', files: ['src/model.ts'] }
        };
      }
      seenVerifierPrompt = prompt;
      return { verdicts: [{ id: 'code_quality-0-1', verdict: 'REFUTED', severity: 'Important', reason: 'out of scope' }] };
    }
  };
  await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  assert.ok(seenVerifierPrompt.includes('HUNK SCOPE'));
  assert.ok(seenVerifierPrompt.includes('REFUTE any CONFIRMED finding that is out of scope'));
});
