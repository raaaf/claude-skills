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

function hasCompleteCoverage(result, paths) {
  const coverage = result && result.coverage;
  return result && Array.isArray(result.findings) && coverage && coverage.status === 'complete' && Array.isArray(coverage.files) &&
    coverage.files.every((path) => typeof path === 'string' && paths.includes(path)) &&
    paths.every((path) => coverage.files.includes(path));
}

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
    coverage: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['complete', 'incomplete'] },
        files: { type: 'array', items: { type: 'string' } }
      },
      required: ['status', 'files']
    }
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

// Prepended to every agent briefing so a fixer/verifier reads the audited
// repo, not the directory the Workflow tool happened to launch from (same
// round-2 defect as find.js).
const ROOT_HEADER = `REPO_ROOT=${args.repoRoot}\n` +
  'Audit and edit source files only inside REPO_ROOT. Relative source paths resolve as REPO_ROOT/<path>. ' +
  'Read absolute instruction-document paths exactly as supplied, including documents outside REPO_ROOT. ' +
  'Do not use the current working directory, it may be a different repository.\n\n';

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
// args: { repoRoot, fixes: [{file, findings}], testCommand, baselineFailures, budget, auditBin, promptDir }
const budget = args.budget || 25;
const auditBin = args.auditBin;
const promptDir = args.promptDir || `${auditBin}/../agents`;
const testCommand = args.testCommand;
const baselineFailures = args.baselineFailures || [];

const excluded = (args.fixes || []).flatMap((f) => f.findings.filter((finding) => finding.severity === 'Minor').map((finding) => finding.id));
const requested = (args.fixes || []).map((f) => ({ ...f, findings: f.findings.filter((finding) => finding.severity !== 'Minor') }));
const uncovered = [];

// Stage 1: one fixer per file, all actionable findings in one dispatch.
const fixerSlots = await parallel(requested.map((f) => async () => {
  if (!f.findings.length) return { ...f, fix: null, verdict: null, status: 'skipped' };
  const result = await agent(
    ROOT_HEADER +
    `Read ${promptDir}/fix-agent.md and fix every finding below in ${f.file}. Do not touch any other ` +
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
const fixResults = requested.map((f, i) => fixerSlots[i] || { ...f, fix: null });
log(`fix.js: ${fixResults.filter((r) => r.fix).length}/${requested.length} fixers reported`);

function hasOwnedChange(result) {
  return result.fix && Array.isArray(result.fix.files) &&
    result.fix.files.length === 1 && result.fix.files[0] === result.file;
}

// Stage 2: fix-verifier per 3-5 fixes.
const appliedOrPartial = fixResults.filter(
  (r) => hasOwnedChange(r) && (r.fix.fix_result === 'APPLIED' || r.fix.fix_result === 'PARTIAL')
);
const verifierGroups = chunk(appliedOrPartial, 4);
const verifierResults = await parallel(verifierGroups.map((group) => async () => {
  const result = await agent(
    ROOT_HEADER +
    `Read ${promptDir}/fix-verifier.md and verify these fixes.\nFIXES=${JSON.stringify(group)}\n` +
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
const verified = verifierGroups.flatMap((group, i) => verifierResults[i] || group.map((g) => ({ ...g, verdict: null })));
for (const result of fixResults) {
  const verification = verified.find((v) => v.file === result.file);
  result.verdict = verification && verification.verdict || null;
  if (result.status !== 'skipped') {
    result.status = hasOwnedChange(result) && result.fix.fix_result === 'APPLIED' && result.verdict &&
      result.verdict.verdict === 'VERIFIED' && Array.isArray(result.verdict.regressions) &&
      result.verdict.regressions.length === 0 ? 'complete' : 'incomplete';
    if (result.status === 'incomplete') uncovered.push(`fix:${result.file}`);
  }
}

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
      ROOT_HEADER +
      `Read the diffs of these files (git diff for each) and check for regressions across all ` +
      `13 dimensions, using the specialist schema. Diffs only, no unrelated reading.\n` +
      `Return coverage={status:"complete"|"incomplete",files:[reviewed paths]}. Only mark complete after reviewing every assigned file.\n` +
      `FILES=${JSON.stringify(group)}`,
      { agentType: 'code-reviewer', model: 'sonnet', schema: FINDINGS_SCHEMA, phase: 'Regress' }
    );
    if (warnIfNull(log, result, `fix.js: a regression pass returned null for ${group.join(', ')}`)) return null;
    return result;
  }));
  regressionGroups.forEach((group, i) => {
    if (!hasCompleteCoverage(regressionResults[i], group)) {
      uncovered.push(...group.map((file) => `regression:${file}`));
      for (const result of fixResults) {
        if (result.fix && result.fix.files.some((file) => group.includes(file))) result.status = 'incomplete';
      }
    }
  });
  regressions = regressionResults.filter((result) => result && Array.isArray(result.findings)).flatMap((result) => result.findings);
}

const blockingRegressions = regressions.filter(
  (r) => r.severity === 'Critical' || r.severity === 'Important'
);
if (blockingRegressions.length) {
  log(`fix.js: ${blockingRegressions.length} regression(s) at Critical/Important, blocking the marker`);
  for (const result of fixResults) {
    if (result.status === 'complete') result.status = 'incomplete';
  }
}

return {
  status: uncovered.length || blockingRegressions.length ? 'incomplete' : 'complete',
  fixes: fixResults,
  uncovered,
  excluded,
  verdicts: verified.map((v) => v.verdict).filter(Boolean),
  regressions,
  rejected: rejected.map((r) => r.file),
  blockingRegressions
};
