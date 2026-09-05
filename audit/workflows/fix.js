export const meta = {
  name: 'audit-fix',
  description: 'Fix pipeline for /audit and /full-audit: fixer per file, fix-verifier per group, regression pass.',
  phases: [{ title: 'Fix' }, { title: 'Verify' }, { title: 'Regress' }]
};

// audit/workflows/fix.js
//
// Fix pipeline: one fixer per file (all findings for that file), a fix-verifier
// per 3-5 fixes, then a regression pass over the changed files. Plain
// JavaScript, no TypeScript, no npm dependency, no Date.now(), no Math.random().
// Dispatched via `Workflow({ scriptPath: 'audit/workflows/fix.js', args, resumeFromRunId })`.
//
// Same Workflow-Kontrakt as find.js (audit/references/finding-schema.md): this
// is a plain top-level program, NOT an ES module — `export const meta = {...}`
// (pure literal) is the FIRST statement, no other import/export anywhere, and
// `agent`, `parallel`, `log`, `args` are runtime-provided globals. agent()
// returns the schema-validated object, parallel() returns null for a failed
// slot, resumeFromRunId replays cached agents.

// JSON schemas for agent replies, copied from audit/references/finding-schema.md.
// FINDINGS_SCHEMA is duplicated from find.js because this file cannot import
// from another script under the Workflow-tool contract (no imports allowed).

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    fix_result: { type: 'string', enum: ['APPLIED', 'PARTIAL', 'NOT_FOUND', 'SUPPRESSED', 'FAILED'] },
    files: { type: 'array', items: { type: 'string' } },
    diff_summary: { type: 'string' },
    test: { type: 'string' },
    tool_calls: { type: 'integer' }
  },
  required: ['fix_result', 'files', 'diff_summary', 'test', 'tool_calls']
};

const FIX_VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['VERIFIED', 'PARTIAL', 'REJECT'] },
    regressions: { type: 'array', items: { type: 'string' } },
    tests: { type: 'string' }
  },
  required: ['verdict', 'regressions', 'tests']
};

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['Critical', 'Important', 'Minor'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          files: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                lines: { type: 'string' }
              },
              required: ['path', 'lines']
            }
          },
          issue: { type: 'string' },
          impact: { type: 'string' }
        },
        required: ['id', 'severity', 'confidence', 'files', 'issue', 'impact']
      }
    },
    coverage: { type: 'string' }
  },
  required: ['findings', 'coverage']
};

// Null-guard for a failed/aborted agent() call. Duplicated from find.js
// (imports are impossible under the Workflow-tool contract); kept as a 5-line
// helper rather than inlined at every call site.
function warnIfNull(logFn, result, message) {
  if (!result) {
    logFn(message);
    return true;
  }
  return false;
}

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

// Groups changed files into 5-8 file regression groups (same chunking shape as
// find.js's chunkByDirectory, but regression groups don't need directory
// affinity — every group just needs the diffs of its files).
function groupForRegression(files) {
  const groups = [];
  for (let i = 0; i < files.length; i += 7) {
    groups.push(files.slice(i, i + 7));
  }
  // Merge a trailing group under 5 into the previous one when there is one.
  if (groups.length > 1 && groups[groups.length - 1].length < 5) {
    const last = groups.pop();
    groups[groups.length - 1] = groups[groups.length - 1].concat(last);
  }
  return groups;
}

// Entry point: this script body IS the run, invoked by the Workflow tool with
// `agent`, `parallel`, `log`, `args` already in scope as globals.
// args: { repoRoot, fixes: [{file, findings}], testCommand, baselineFailures, budget, auditBin }
const budget = args.budget || 25;
const auditBin = args.auditBin;
const testCommand = args.testCommand;
const baselineFailures = args.baselineFailures || [];

// Stage 1: one fixer per file, all its findings in one dispatch.
const fixResults = await parallel(args.fixes.map((f) => async () => {
  const result = await agent(
    `Read agents/fix-agent.md and fix every finding below in ${f.file}. Do not touch any other ` +
    `file.\nFINDINGS=${JSON.stringify(f.findings)}\n` +
    `TEST_COMMAND=bash ${auditBin}/test-lock.sh ${testCommand}\n` +
    `BASELINE_FAILURES=${JSON.stringify(baselineFailures)}\nBUDGET=${budget}`,
    { agentType: 'audit-fix-agent', model: 'sonnet', schema: FIX_SCHEMA, phase: 'Fix' }
  );
  if (warnIfNull(log, result, `fix.js: fixer for ${f.file} returned null`)) {
    return { file: f.file, findings: f.findings, fix: null };
  }
  return { file: f.file, findings: f.findings, fix: result };
}));
log(`fix.js: ${fixResults.filter((r) => r.fix).length}/${args.fixes.length} fixers reported`);

// Stage 2: fix-verifier per 3-5 fixes.
const appliedOrPartial = fixResults.filter(
  (r) => r.fix && (r.fix.fix_result === 'APPLIED' || r.fix.fix_result === 'PARTIAL')
);
const verifierGroups = chunk(appliedOrPartial, 4);
const verifierResults = await parallel(verifierGroups.map((group) => async () => {
  const result = await agent(
    `Read agents/fix-verifier.md and verify these fixes.\nFIXES=${JSON.stringify(group)}\n` +
    `BASELINE_FAILURES=${JSON.stringify(baselineFailures)}\n` +
    `TEST_COMMAND=bash ${auditBin}/test-lock.sh ${testCommand}`,
    { agentType: 'audit-fix-verifier', model: 'sonnet', schema: FIX_VERDICT_SCHEMA, phase: 'Verify' }
  );
  if (warnIfNull(log, result, `fix.js: a fix-verifier group returned null (${group.length} fixes unverified)`)) {
    return group.map((g) => ({ ...g, verdict: null }));
  }
  // One verdict object covers the whole group in this schema; attach it to
  // every fix in the group, the orchestrator reads per-fix reasoning from
  // `regressions` entries that name the file.
  return group.map((g) => ({ ...g, verdict: result }));
}));
const verified = verifierResults.flat();

const rejected = verified.filter((v) => v.verdict && v.verdict.verdict === 'REJECT');
if (rejected.length) {
  log(`fix.js: ${rejected.length} fix(es) rejected by fix-verifier, staying open (no second round)`);
}

// Stage 3: regression pass over every file a fixer actually changed.
const changedFiles = [...new Set(
  fixResults.filter((r) => r.fix && r.fix.files && r.fix.files.length).flatMap((r) => r.fix.files)
)];
let regressions = [];
if (changedFiles.length) {
  const regressionGroups = groupForRegression(changedFiles);
  const regressionResults = await parallel(regressionGroups.map((group) => async () => {
    const result = await agent(
      `Read the diffs of these files (git diff for each) and check for regressions across all ` +
      `13 dimensions, using the specialist schema. Diffs only, no unrelated reading.\n` +
      `FILES=${JSON.stringify(group)}`,
      { agentType: 'code-reviewer', model: 'sonnet', schema: FINDINGS_SCHEMA, phase: 'Regress' }
    );
    if (warnIfNull(log, result, `fix.js: a regression pass returned null for ${group.join(', ')}`)) return [];
    return result.findings;
  }));
  regressions = regressionResults.flat();
}

const blockingRegressions = regressions.filter(
  (r) => r.severity === 'Critical' || r.severity === 'Important'
);
if (blockingRegressions.length) {
  log(`fix.js: ${blockingRegressions.length} regression(s) at Critical/Important, blocking the marker`);
}

return {
  fixes: verified,
  verdicts: verified.map((v) => v.verdict).filter(Boolean),
  regressions,
  rejected: rejected.map((r) => r.file),
  blockingRegressions
};
