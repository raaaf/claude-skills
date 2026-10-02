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

// Effort cap for security-auditor inside /audit (2026-09-30): the agent's frontmatter says
// effort max for standalone security audits; in the find pipeline that doubled context per call
// (101k -> 192k) and made security/privacy/payments 48% of find cost. find.js passes effort
// 'high' for those dispatches only; other specialists keep their frontmatter effort.
test('security-auditor specialists run at effort high, other specialists inherit', async () => {
  const args = baseArgs({ dimensions: ['code_quality', 'security', 'payments'] });
  const { prompts } = await runWorkflow(args);
  const audit = prompts.filter((p) => p.options.phase === 'Audit');
  const sec = audit.filter((p) => p.options.agentType === 'security-auditor');
  const other = audit.filter((p) => p.options.agentType !== 'security-auditor');
  assert.ok(sec.length >= 2 && other.length >= 1);
  for (const p of sec) assert.equal(p.options.effort, 'high');
  for (const p of other) assert.equal(p.options.effort, undefined);
});

// Hunk-scoped coverage (2026-10-01): under hunkScope, findings are limited to changed hunks, yet the
// coverage contract still demanded every assigned file be read in full. In the three HUGE runs of
// 2026-10-01 that put specialists at 120-200k context per call (docs_sync median 202k). Under
// hunkScope the contract is the changed hunks; payments keeps the full-file contract (whole
// STRIPE_FILES surface by design), and without hunkScope nothing changes.
test('hunkScope on: specialists cover changed hunks, not whole files; payments and off stay whole-file', async () => {
  const on = await runWorkflow(baseArgs({ hunkScope: true, baseRef: 'origin/main' }));
  const cq = on.prompts.find((p) => p.options.phase === 'Audit' && p.prompt.includes('DIMENSION=code_quality'));
  const pay = on.prompts.find((p) => p.options.phase === 'Audit' && p.prompt.includes('DIMENSION=payments'));
  assert.ok(cq.prompt.includes('COVERAGE CONTRACT (hunk scope)'));
  assert.ok(!cq.prompt.includes('Read every one of these files in full'));
  assert.ok(pay.prompt.includes('Read every one of these files in full'));
  const off = await runWorkflow(baseArgs({}));
  const cqOff = off.prompts.find((p) => p.options.phase === 'Audit' && p.prompt.includes('DIMENSION=code_quality'));
  assert.ok(cqOff.prompt.includes('Read every one of these files in full'));
  assert.ok(!cqOff.prompt.includes('COVERAGE CONTRACT (hunk scope)'));
});

// Precomputed hunks (2026-10-02): reviewer agents (ui-ux-reviewer, code-reviewer) have no Bash, so the
// "run git diff" instruction could never be followed. With args.hunks the prompts carry the ranges and
// no git-diff instruction; without it the old text stays.
test('hunks given: specialist prompt carries the ranges and no git-diff instruction', async () => {
  const hunks = { 'src/model.ts': [[1, 40], [80, 95]], 'app/Billing/Charge.php': 'whole' };
  const { prompts } = await runWorkflow(baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true, baseRef: 'origin/main', hunks }));
  const audit = prompts.filter((p) => p.options.phase === 'Audit');
  assert.ok(audit.length > 0);
  for (const p of audit) {
    assert.ok(p.prompt.includes('[[1,40],[80,95]]'));
    assert.ok(!p.prompt.includes('git -C REPO_ROOT diff'));
    assert.ok(!/(?<!not )run (the )?git diff/.test(p.prompt));
    assert.ok(p.prompt.includes('read the line ranges listed in HUNK SCOPE'));
  }
});

test('hunks missing: the old git-diff text stays', async () => {
  const { prompts } = await runWorkflow(baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true, baseRef: 'origin/main' }));
  for (const p of prompts.filter((q) => q.options.phase === 'Audit')) {
    assert.ok(p.prompt.includes('git -C REPO_ROOT diff origin/main -U15'));
    assert.ok(p.prompt.includes('run the git diff from HUNK SCOPE'));
  }
});

test('hunks given: the verifier prompt carries the ranges of the finding files', async () => {
  const args = baseArgs({ dimensions: ['code_quality'], dimensionFiles: {}, hunkScope: true, baseRef: 'origin/main', hunks: { 'src/model.ts': [[2, 9]], 'other.ts': [[1, 1]] } });
  let verifierPrompt = null;
  const context = {
    args, log() {}, performance: { now: () => 0 },
    parallel: (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    agent: async (prompt, options) => {
      if (options.phase === 'Scout') return scoutFilesStub(prompt);
      if (options.phase === 'Audit') {
        return { findings: [{ id: 'code_quality-0-1', severity: 'Important', confidence: 'high',
          files: [{ path: 'src/model.ts', lines: '3' }], issue: 'x', impact: 'y' }], coverage: { status: 'complete', files: ['src/model.ts'] } };
      }
      verifierPrompt = prompt;
      return { verdicts: [{ id: 'code_quality-0-1', verdict: 'CONFIRMED', severity: 'Important', reason: 'ok' }] };
    }
  };
  await vm.runInNewContext(`(async () => {\n${workflowSource}\n})()`, context, { filename: workflowPath });
  assert.ok(verifierPrompt.includes('{"src/model.ts":[[2,9]]}'));
  assert.ok(!verifierPrompt.includes('other.ts'));
  assert.ok(!verifierPrompt.includes('git -C REPO_ROOT diff'));
});
