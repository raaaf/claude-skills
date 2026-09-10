export const meta = {
  name: 'audit-find',
  description: 'Per-dimension find pipeline for /audit and /full-audit: scout, chunk, specialists, verify.',
  phases: [{ title: 'Scout' }, { title: 'Audit' }, { title: 'Verify' }]
};

// audit/workflows/find.js
//
// Per-dimension find pipeline for /audit and /full-audit. Plain JavaScript, no
// TypeScript, no npm dependency, no Date.now(), no Math.random() (Konventionen,
// CLAUDE.md). Dispatched via the Workflow tool: `Workflow({ scriptPath: 'audit/workflows/find.js',
// args, resumeFromRunId })`.
//
// Contract this script relies on (audit/references/finding-schema.md,
// "Workflow-Kontrakt, geprueft am 2026-09-05"):
//   - This is a plain top-level program, NOT an ES module. The Workflow tool
//     requires `export const meta = {...}` (a pure literal) as the FIRST
//     statement and provides the globals `agent`, `parallel`, `pipeline`,
//     `phase`, `log`, `args` at the top level. No other `import`/`export`
//     anywhere in this file.
//   - agent(prompt, opts) with opts.agentType / opts.model / opts.schema returns the
//     schema-validated object directly (no JSON.parse needed). `schema` must be a
//     real JSON-Schema object, never a string.
//   - parallel(thunks) resolves every thunk; a thrown/aborted agent comes back as
//     null in its slot instead of rejecting the whole parallel() call.
//   - log(message) surfaces a line in the run's live progress (`/workflows`).
//   - resumeFromRunId replays completed agents from cache when script + args are
//     unchanged.

// JSON schemas for agent replies, copied from audit/references/finding-schema.md.
// Duplicated in fix.js (FINDINGS_SCHEMA) because this file cannot import from
// another script under the Workflow-tool contract (no imports allowed).

const SCOUT_FILES_SCHEMA = {
  type: 'object',
  properties: {
    files: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          tag: { type: 'string', enum: ['floor', 'scope', 'context'] },
          reason: { type: 'string' }
        },
        required: ['path', 'tag', 'reason']
      }
    }
  },
  required: ['files']
};

const SCOUT_CLUSTERS_SCHEMA = {
  type: 'object',
  properties: {
    clusters: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          pattern: { type: 'string' },
          files: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                path: { type: 'string' },
                count: { type: 'integer' }
              },
              required: ['path', 'count']
            }
          },
          why: { type: 'string' }
        },
        required: ['id', 'pattern', 'files', 'why']
      }
    }
  },
  required: ['clusters']
};

function hasCompleteCoverage(result, paths) {
  const coverage = result && result.coverage;
  return coverage && coverage.status === 'complete' && Array.isArray(coverage.files) &&
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

const VERDICTS_SCHEMA = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'UNCERTAIN'] },
          severity: { type: 'string', enum: ['Critical', 'Important', 'Minor'] },
          reason: { type: 'string' }
        },
        required: ['id', 'verdict', 'severity', 'reason']
      }
    }
  },
  required: ['verdicts']
};

// Null-guard for a failed/aborted agent() call. Duplicated in fix.js (imports
// are impossible under the Workflow-tool contract); kept as a 5-line helper
// rather than inlined at every call site.
function warnIfNull(logFn, result, message) {
  if (!result) {
    logFn(message);
    return true;
  }
  return false;
}

// Prepended to every agent briefing so a specialist reads the audited repo,
// not the directory the Workflow tool happened to launch from (round-2 defect:
// 4 of 6 specialists answered "file does not exist" because the briefing never
// named the repo root).
const ROOT_HEADER = `REPO_ROOT=${args.repoRoot}\n` +
  'Audit and edit source files only inside REPO_ROOT. Relative source paths resolve as REPO_ROOT/<path>. ' +
  'Read absolute instruction-document paths exactly as supplied, including documents outside REPO_ROOT. ' +
  'Do not use the current working directory, it may be a different repository.\n\n';

// agentType per dimension (Step 4 of the plan).
const AGENT_TYPE_BY_DIMENSION = {
  security: 'security-auditor',
  privacy: 'security-auditor',
  performance: 'performance-auditor',
  a11y: 'ui-ux-reviewer',
  ui_design: 'ui-ux-reviewer',
  ux: 'ui-ux-reviewer',
  typography: 'ui-ux-reviewer',
  animation: 'ui-ux-reviewer',
  architecture: 'code-reviewer',
  code_quality: 'code-reviewer',
  seo: 'code-reviewer',
  docs_sync: 'code-reviewer',
  copy: 'code-reviewer',
  payments: 'security-auditor'
};

// Dimensions that use ONLY the cluster scout (no file scout).
const CLUSTER_ONLY_DIMENSIONS = ['architecture', 'docs_sync'];
// Dimensions that use BOTH scouts (results merge in Stage 2).
const BOTH_SCOUTS_DIMENSIONS = ['security'];

const ALL_DIMENSIONS = [
  'architecture', 'security', 'performance', 'code_quality', 'seo', 'a11y',
  'typography', 'ui_design', 'ux', 'animation', 'docs_sync', 'copy', 'privacy',
  'payments'
];

// Mirrors audit/bin/lib-git-base.sh FRONTEND_EXT_RE (single source of truth is the
// shared bash lib; kept in sync here because find.js runs outside bash).
const FRONTEND_EXT_RE = /\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$/i;
const TRANSLATION_RE = /(^|\/)(lang|locales|translations|messages|i18n)\/.*\.(php|json|ya?ml|po|ts)$/i;
const MIGRATION_RE = /(^|\/)(migrations?|db\/migrate)\//i;
const DOCS_RE = /(^|\/)(README\.md|CLAUDE\.md|docs\/.*\.md|\.env\.example)$/i;
const SEO_RE = /(sitemap|robots\.txt|routes?\/|templates?\/)/i;

// Deterministic floor: which dimensions this file is assigned to regardless of
// what a scout picks, per CLAUDE.md "Triage routing has a deterministic floor".
function floorDimensionsForFile(path) {
  const dims = [];
  if (FRONTEND_EXT_RE.test(path)) {
    dims.push('a11y', 'ui_design', 'ux', 'animation', 'seo');
  }
  if (TRANSLATION_RE.test(path)) {
    dims.push('copy', 'typography', 'privacy');
  }
  if (MIGRATION_RE.test(path)) {
    dims.push('architecture');
  }
  if (DOCS_RE.test(path)) {
    dims.push('docs_sync');
  }
  if (SEO_RE.test(path)) {
    dims.push('seo');
  }
  if (/\.(php|ts|tsx|js|jsx|py|rb|go|swift|kt|java|sh)$/i.test(path)) {
    dims.push('code_quality', 'security', 'performance');
  }
  return dims;
}

// FILE FLOOR vs. DIMENSION GATE: floorDimensionsForFile is a per-file SIGNAL
// (which dimensions this file's path is relevant to), not a per-file
// OBLIGATION. Measured 2026-09-06 against the real 257-file corpus (CLAUDE.md
// gotcha "Triage routing has a deterministic floor" describes the floor at
// DIMENSION granularity, i.e. "should this dimension run at all" — it never
// claimed "this file must appear in the dimension's scout list"):
//   security 238, performance 238, code_quality 238, seo 122, a11y 122,
//   ui_design 122, ux 122, animation 122, architecture 0, typography 0,
//   docs_sync 0, copy 0, privacy 0
// Applying the signal as a per-file floor for the broad dimensions makes
// MAX_SCOUT_FILES=70 inert (a rule matching most of the repo is not a
// signal, it is the whole repository) and forces the scout to keep a
// near-total file set. Only the narrow, genuinely selective signals
// (DOCS_RE, TRANSLATION_RE, MIGRATION_RE match a small precise set) stay a
// per-file obligation. Do not add a dimension back here without
// re-measuring against the corpus above.
const SELECTIVE_FLOOR_DIMENSIONS = ['docs_sync', 'copy', 'typography', 'architecture'];

// Soft cap on a dimension's scout list, shared by computeFloorFiles (logs
// when the content floor alone exceeds it) and runFileScout (measured
// 2026-09-06, a scout given "do not thin the list" stopped narrowing at all:
// 203/209/199/150/141/139 files across 6 dimensions, 273 agents total, 124
// USD against a 100 USD target). Floor entries are never dropped; non-floor
// entries beyond the cap are dropped in scout order.
const MAX_SCOUT_FILES = 70;

// CONTENT-based floor: replaces the extension-based per-file floor for the
// broad dimensions above (measured 2026-09-06, see the note above this
// block). A path-based floor over FRONTEND_EXT_RE/`.php|ts|...` matches most
// of a real repo, which makes MAX_SCOUT_FILES inert. The actual signals
// (regex source + explanatory comments) live in audit/floor-signals.json,
// the single source of truth, and are computed OUTSIDE this script by
// audit/bin/compute-floor.mjs since find.js has no filesystem access; the
// result arrives here as args.floorFiles, a {dimension: [paths]} map.
// `architecture` intentionally has no content signal: it keeps the existing
// selective PATH-based floor only.

// Content-based floor: a file joins a dimension's floor when its content
// matched at least one of that dimension's signals in floor-signals.json,
// already computed by the caller via audit/bin/compute-floor.mjs into
// `floorFiles[dimension]`. A dimension absent from `floorFiles` simply
// yields no content floor and falls back to the scout (and is reported
// under degradedDimensions below).
function computeFloorFiles(dimension, files, floorFiles, logFn) {
  const pathFloor = SELECTIVE_FLOOR_DIMENSIONS.includes(dimension)
    ? files.filter((f) => floorDimensionsForFile(f).includes(dimension))
    : [];
  const contentFloor = (floorFiles && floorFiles[dimension]) || [];
  const merged = pathFloor.slice();
  for (const f of contentFloor) {
    if (!merged.includes(f)) merged.push(f);
  }
  if (merged.length > MAX_SCOUT_FILES && logFn) {
    logFn(`${dimension}: content floor alone has ${merged.length} file(s), above the ${MAX_SCOUT_FILES}-file cap; floor entries are never dropped`);
  }
  return merged;
}

// DIMENSION GATE: true when at least one file in scope carries this
// dimension's signal. A dimension still runs when this is false (the scout
// may find something the signal regexes miss); this only decides whether to
// log that the dimension has no deterministic signal at all.
function dimensionHasFloorSignal(dimension, files) {
  return files.some((f) => floorDimensionsForFile(f).includes(dimension));
}

function chunk(files, size) {
  const out = [];
  for (let i = 0; i < files.length; i += size) {
    out.push(files.slice(i, i + size));
  }
  return out;
}

// Groups a flat file list into 5-8 file chunks, keeping files from the same
// directory together where possible (Edge Cases: "Scout liefert ueber 60
// Dateien").
function chunkByDirectory(files) {
  const byDir = {};
  for (const f of files) {
    const dir = f.includes('/') ? f.slice(0, f.lastIndexOf('/')) : '.';
    (byDir[dir] = byDir[dir] || []).push(f);
  }
  const dirGroups = Object.values(byDir);
  const chunks = [];
  let current = [];
  for (const group of dirGroups) {
    if (group.length >= 5 && group.length <= 8) {
      if (current.length) { chunks.push(current); current = []; }
      chunks.push(group);
      continue;
    }
    for (const f of group) {
      current.push(f);
      if (current.length === 8) { chunks.push(current); current = []; }
    }
  }
  if (current.length) chunks.push(current);
  // Re-merge any trailing chunk under 5 files into the previous one.
  for (let i = chunks.length - 1; i > 0; i--) {
    if (chunks[i].length < 5) {
      chunks[i - 1] = chunks[i - 1].concat(chunks[i]);
      chunks.splice(i, 1);
    }
  }
  return chunks;
}

// A dimension listed in ctx.dimensionFiles scouts its own file list (e.g.
// payments/STRIPE_FILES) instead of the shared diff/repo scope; every other
// dimension falls back to ctx.files unchanged.
function scopeFilesFor(ctx, dimension) {
  return (ctx.dimensionFiles && ctx.dimensionFiles[dimension]) || ctx.files;
}

async function runFileScout(ctx, dimension, agentFn, logFn) {
  const promptDoc = `${ctx.promptDir}/scout-files.md`;
  const scopeFiles = scopeFilesFor(ctx, dimension);
  const floorFiles = computeFloorFiles(dimension, scopeFiles, ctx.floorFiles, logFn);
  if (!floorFiles.length && !dimensionHasFloorSignal(dimension, scopeFiles)) {
    logFn(`${dimension}: no deterministic floor signal in scope, relying entirely on the scout`);
  }
  const floorFilesBriefing = floorFiles.length
    ? JSON.stringify(floorFiles)
    : '(none for this dimension; select under the concrete-trigger rule and stay within MAX_SCOUT_FILES)';
  const result = await agentFn(
    ROOT_HEADER +
    `Read ${promptDoc} and execute the file-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(scopeFiles)}\nFLOOR_FILES=${floorFilesBriefing}\n` +
    `SCOPE=${ctx.scope}`,
    { agentType: 'Explore', model: 'sonnet', schema: SCOUT_FILES_SCHEMA, phase: 'Scout' }
  );
  if (warnIfNull(logFn, result, `${dimension}: file scout returned null, using floor files only`)) {
    return { failed: true, files: floorFiles.map((path) => ({ path, tag: 'floor', reason: 'scout unavailable' })) };
  }
  // Code-side floor enforcement: a missing floor file is added back, never
  // silently dropped (Step 3 contract).
  const covered = new Set(result.files.map((f) => f.path));
  const added = [];
  for (const f of floorFiles) {
    if (!covered.has(f)) {
      result.files.push({ path: f, tag: 'floor', reason: 'floor file added back by find.js' });
      added.push(f);
    }
  }
  if (added.length) {
    logFn(`${dimension}: scout omitted ${added.length} floor file(s), re-added: ${added.join(', ')}`);
  }
  if (result.files.length > MAX_SCOUT_FILES) {
    const floorEntries = result.files.filter((f) => floorFiles.includes(f.path));
    const nonFloorEntries = result.files.filter((f) => !floorFiles.includes(f.path));
    const nonFloorKeep = Math.max(0, MAX_SCOUT_FILES - floorEntries.length);
    const kept = floorEntries.concat(nonFloorEntries.slice(0, nonFloorKeep));
    const dropped = result.files.length - kept.length;
    logFn(`${dimension}: scout returned ${result.files.length} files, kept ${kept.length}, dropped ${dropped}`);
    return { files: kept };
  }
  return { files: result.files };
}

async function runClusterScout(ctx, dimension, agentFn, logFn) {
  const promptDoc = `${ctx.promptDir}/scout-clusters.md`;
  const result = await agentFn(
    ROOT_HEADER +
    `Read ${promptDoc} and execute the cluster-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(scopeFilesFor(ctx, dimension))}`,
    { agentType: 'Explore', model: 'sonnet', schema: SCOUT_CLUSTERS_SCHEMA, phase: 'Scout' }
  );
  if (warnIfNull(logFn, result, `${dimension}: cluster scout returned null`)) return { failed: true, clusters: [] };
  return { clusters: result.clusters };
}

async function runDimension(ctx, dimension, agentFn, parallelFn, logFn) {
  // Stage 1: retain scout failures independently from deterministic floor coverage.
  const scoutJobs = [];
  if (!CLUSTER_ONLY_DIMENSIONS.includes(dimension)) {
    scoutJobs.push(['files', () => runFileScout(ctx, dimension, agentFn, logFn)]);
  }
  if (CLUSTER_ONLY_DIMENSIONS.includes(dimension) || BOTH_SCOUTS_DIMENSIONS.includes(dimension)) {
    scoutJobs.push(['clusters', () => runClusterScout(ctx, dimension, agentFn, logFn)]);
  }
  const scoutResults = await parallelFn(scoutJobs.map((job) => job[1]));
  const uncovered = [];
  let files = [];
  let clusters = [];
  scoutJobs.forEach(([kind], i) => {
    const result = scoutResults[i];
    if (!result || result.failed) uncovered.push(`scout:${kind}`);
    if (kind === 'files') files = result && result.files || [];
    else clusters = result && result.clusters || [];
  });
  if (files.length === 0 && clusters.length === 0) {
    const status = uncovered.length ? 'incomplete' : 'skipped';
    logFn(`${dimension}: ${status}, no relevant files`);
    return { status, files: [], chunks: 0, findings: [], verdicts: [], uncovered, unverified: [], unrefuted: [] };
  }

  // Stage 2: chunking (code, not an agent).
  const filePaths = files.map((f) => f.path);
  // A cluster naming fewer than 2 files is not a cluster (scout-clusters.md
  // "at least two files"); drop it rather than dispatching a specialist that
  // sees a single file with no comparison to make.
  clusters = clusters.filter((cluster, index) => {
    const valid = cluster && typeof cluster.id === 'string' && cluster.id.trim() &&
      typeof cluster.pattern === 'string' && cluster.pattern.trim() &&
      Array.isArray(cluster.files) && cluster.files.length >= 2 &&
      cluster.files.every((file) => file && typeof file.path === 'string' && file.path.trim() &&
        Number.isInteger(file.count) && file.count > 0) &&
      new Set(cluster.files.map((file) => file.path)).size === cluster.files.length;
    if (!valid) uncovered.push(`cluster:${cluster && cluster.id || index}`);
    return valid;
  });
  const fileChunks = chunkByDirectory(filePaths).map((group) => ({ kind: 'files', files: group }));
  const clusterChunks = clusters.map((c) => ({ kind: 'cluster', cluster: c }));
  let chunks;
  if (CLUSTER_ONLY_DIMENSIONS.includes(dimension)) {
    chunks = clusterChunks;
  } else if (BOTH_SCOUTS_DIMENSIONS.includes(dimension)) {
    chunks = fileChunks.concat(clusterChunks);
  } else {
    chunks = fileChunks;
  }
  logFn(`${dimension}: scout ${filePaths.length || clusters.length} unit(s), ${chunks.length} chunk(s)`);
  if (chunks.length > 15) {
    logFn(`${dimension}: ${chunks.length} chunks, above the 15-chunk expectation`);
  }

  const agentType = AGENT_TYPE_BY_DIMENSION[dimension];
  const dimDoc = ctx.dimensionDoc[dimension];

  // Stage 3: specialists, one per chunk, in parallel.
  const specialistResults = await parallelFn(chunks.map((c, i) => async () => {
    const briefing = c.kind === 'cluster'
      ? `CLUSTER=${JSON.stringify(c.cluster)}`
      : `FILES=${JSON.stringify(c.files)}`;
    const dimContext = (ctx.dimensionContext && ctx.dimensionContext[dimension]) || '';
    const result = await agentFn(
      ROOT_HEADER +
      `Read ${ctx.promptDir}/prompt-template.md and ${dimDoc} and execute the specialist task ` +
      `for DIMENSION=${dimension}.\nCHUNK_INDEX=${i}\n${briefing}\n` +
      `GUIDELINES_DIR=${ctx.guidelinesDir}\nMATCHED_GUIDELINES=${ctx.guidelines}\n` +
      `SCOPE=${ctx.scope}` + (dimContext ? `\n${dimContext}` : ''),
      { agentType, model: 'sonnet', schema: FINDINGS_SCHEMA, phase: 'Audit' }
    );
    if (warnIfNull(logFn, result, `${dimension}: specialist for chunk ${i} returned null`)) return null;
    return result;
  }));
  const specialists = specialistResults.filter(Boolean);
  logFn(`${dimension}: ${specialists.length}/${chunks.length} specialists done`);

  chunks.forEach((c, i) => {
    if (!hasCompleteCoverage(specialistResults[i], c.kind === 'cluster' ? c.cluster.files.map((file) => file.path) : c.files)) {
      uncovered.push(c.kind === 'cluster' ? c.cluster.id : c.files.join(','));
    }
  });

  const allFindings = dedupeFindings(specialists.flatMap((s) => s.findings), dimension, logFn);

  if (allFindings.length === 0) {
    return { status: uncovered.length ? 'incomplete' : 'complete', files: filePaths, chunks: chunks.length, findings: [], verdicts: [], uncovered, unverified: [], unrefuted: [] };
  }

  const findingIds = new Set(allFindings.map((finding) => finding.id));
  if (findingIds.size !== allFindings.length) {
    uncovered.push('findings:duplicate-id');
    logFn(`${dimension}: duplicate finding IDs prevent unambiguous verification`);
    return { status: 'incomplete', files: filePaths, chunks: chunks.length, findings: allFindings, verdicts: [], uncovered, unverified: [...findingIds], unrefuted: [] };
  }

  // Stage 4: verifier, one agent per 35-40 findings.
  const verifierGroups = chunk(allFindings, 38);
  const verifierResults = await parallelFn(verifierGroups.map((group) => async () => {
    const result = await agentFn(
      ROOT_HEADER +
      `Read ${ctx.promptDir}/finding-verifier.md and verify these findings.\n` +
      `FINDINGS=${JSON.stringify(group)}`,
      { agentType: 'code-reviewer', model: 'sonnet', schema: VERDICTS_SCHEMA, phase: 'Verify' }
    );
    if (warnIfNull(logFn, result, `${dimension}: a verifier group returned null (${group.length} findings uncovered)`)) return null;
    return result.verdicts;
  }));
  const unverified = [];
  const unrefuted = [];
  const verdicts = [];
  verifierGroups.forEach((group, i) => {
    const replies = verifierResults[i];
    const expected = new Set(group.map((f) => f.id));
    if (Array.isArray(replies) && replies.some((v) => !v || !expected.has(v.id))) {
      uncovered.push(`verifier:${i}:unknown-id`);
    }
    for (const finding of group) {
      const matches = Array.isArray(replies) ? replies.filter((v) => v && v.id === finding.id) : [];
      if (matches.length !== 1 || !validVerdict(matches[0])) unverified.push(finding.id);
      else {
        verdicts.push(matches[0]);
        if (matches[0].verdict === 'UNCERTAIN') unverified.push(finding.id);
      }
    }
  });

  // Stage 5: refuter, one per CONFIRMED Critical.
  const criticalConfirmed = verdicts.filter((v) => v.verdict === 'CONFIRMED' && v.severity === 'Critical');
  if (criticalConfirmed.length) {
    const refuterResults = await parallelFn(criticalConfirmed.map((v) => async () => {
      const finding = allFindings.find((f) => f.id === v.id);
      const refuterVerdict = await agentFn(
        ROOT_HEADER +
        `Read ${ctx.promptDir}/finding-verifier.md, section "Refuter". Try to refute this ` +
        `CONFIRMED Critical finding.\nFINDING=${JSON.stringify(finding)}\nVERDICT=${JSON.stringify(v)}`,
        { agentType: 'code-reviewer', model: 'opus', schema: VERDICTS_SCHEMA, phase: 'Verify' }
      );
      return refuterVerdict;
    }));
    refuterResults.forEach((r, i) => {
      const original = criticalConfirmed[i];
      const refuted = r && Array.isArray(r.verdicts) && r.verdicts.length === 1 && r.verdicts[0];
      if (!validVerdict(refuted) || refuted.id !== original.id || refuted.verdict === 'UNCERTAIN') {
        unrefuted.push(original.id);
        original.verdict = 'UNCERTAIN';
        original.reason = `${original.reason} | required refutation incomplete`;
        return;
      }
      if (refuted.verdict === 'REFUTED') {
        original.severity = 'Important';
        original.disputed = true;
        original.reason = `${original.reason} | disputed by refuter: ${refuted.reason}`;
      }
    });
  }

  return {
    status: uncovered.length || unverified.length || unrefuted.length ? 'incomplete' : 'complete',
    files: filePaths,
    chunks: chunks.length,
    findings: allFindings,
    verdicts,
    uncovered,
    unverified,
    unrefuted
  };
}

function validVerdict(verdict) {
  return verdict && typeof verdict.id === 'string' &&
    ['CONFIRMED', 'REFUTED', 'UNCERTAIN'].includes(verdict.verdict) &&
    ['Critical', 'Important', 'Minor'].includes(verdict.severity) && typeof verdict.reason === 'string';
}

const CONFIDENCE_RANK = { high: 3, medium: 2, low: 1 };
// Used by mergeDuplicate: a merged finding carries the highest severity of the set, not the
// severity of whichever finding won the confidence tie-break.
const SEVERITY_RANK = { Critical: 3, Important: 2, Minor: 1 };

// A finding's dedup key: its lowest-sorting file path and the first line number
// mentioned for that path. Within ONE dimension, two findings on the same file within
// five lines of each other are the same defect reported by two chunks; the wording
// differs because different specialists wrote it, so the issue text is not part of the
// key.
function findingDedupKey(finding) {
  const files = (finding.files || []).slice().sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const first = files[0];
  if (!first) return null;
  const lineMatch = /\d+/.exec(first.lines || '');
  return {
    path: first.path,
    line: lineMatch ? parseInt(lineMatch[0], 10) : null
  };
}

function sameDedupKey(a, b) {
  if (!a || !b || a.path !== b.path) return false;
  if (a.line == null || b.line == null) return a.line === b.line;
  return Math.abs(a.line - b.line) <= 5;
}

// A finding's chunk index, parsed from its `{dimension}-{chunkIndex}-{n}` id, used as
// the tie-breaker when two duplicates share the same confidence.
function findingChunkIndex(finding) {
  const m = /-(\d+)-/.exec(finding.id || '');
  return m ? parseInt(m[1], 10) : Infinity;
}

// Confidence-ranked merge of two findings identified as duplicates (same id, or same
// file+line): keeps the higher-confidence one, tie-breaking toward the earlier chunk, and
// records the dropped finding's id/issue in the winner's mergedFrom (deduped by id).
// Shared by collapseDuplicateIds and dedupeFindings so the merge/tie-break/mergedFrom
// bookkeeping exists in exactly one place.
function mergeDuplicate(existing, incoming) {
  const existingRank = CONFIDENCE_RANK[existing.confidence] || 0;
  const newRank = CONFIDENCE_RANK[incoming.confidence] || 0;
  let winner = existing;
  let dropped = incoming;
  if (newRank > existingRank || (newRank === existingRank && findingChunkIndex(incoming) < findingChunkIndex(existing))) {
    winner = incoming;
    dropped = existing;
  }
  const merged = (winner.mergedFrom || []).concat([{ id: dropped.id, issue: dropped.issue }], dropped.mergedFrom || []);
  const seenIds = new Set();
  winner.mergedFrom = merged.filter((m) => (seenIds.has(m.id) ? false : (seenIds.add(m.id), true)));
  // Severity is the MAX of the merged set, never the winner's own. The winner is chosen by
  // confidence, so without this a high-confidence Important absorbing a medium-confidence
  // Critical would silently downgrade it, and the push gate keys on Critical being open.
  // Confidence and issue text still come from the winner: those describe how well the defect
  // was evidenced, which is exactly what the confidence tie-break selected for.
  const raised = SEVERITY_RANK[dropped.severity] > SEVERITY_RANK[winner.severity];
  if (raised) winner.severity = dropped.severity;
  return { winner, dropped, raised };
}

// A dimension prompt can instruct every chunk's specialist to emit the SAME literal id for
// a cross-chunk singleton finding (e.g. payments' payments-dashboard-unanswered), because no
// single specialist can see its siblings to avoid the collision itself. Collapse those here,
// BEFORE the file+line dedup pass and before runDimension's duplicate-id check, so two
// specialists agreeing on one id doesn't mark the whole dimension incomplete.
function collapseDuplicateIds(findings, dimension, logFn) {
  const survivors = [];
  const indexById = new Map();
  for (const finding of findings) {
    const id = finding && finding.id;
    if (id && indexById.has(id)) {
      const idx = indexById.get(id);
      const { winner, dropped, raised } = mergeDuplicate(survivors[idx], finding);
      survivors[idx] = winner;
      logFn(`${dimension}: collapsed duplicate literal id ${dropped.id} into ${winner.id}${raised ? `, severity raised to ${winner.severity}` : ""}`);
      continue;
    }
    survivors.push(finding);
    if (id) indexById.set(id, survivors.length - 1);
  }
  return survivors;
}

// BOTH_SCOUTS_DIMENSIONS runs a file-chunk pass AND a cluster-chunk pass over the same
// files, so two different specialists can independently report the same defect. Merge
// those duplicates here, before the verifier stage sees them, so a real defect isn't
// verified and counted two or three times.
function dedupeFindings(findings, dimension, logFn) {
  const idCollapsed = collapseDuplicateIds(findings, dimension, logFn);
  const survivors = [];
  const keys = [];
  for (const finding of idCollapsed) {
    const key = findingDedupKey(finding);
    if (!key) { survivors.push(finding); keys.push(key); continue; }
    const existingIdx = survivors.findIndex((_, i) => sameDedupKey(keys[i], key));
    if (existingIdx === -1) {
      survivors.push(finding);
      keys.push(key);
      continue;
    }
    const { winner, dropped, raised } = mergeDuplicate(survivors[existingIdx], finding);
    survivors[existingIdx] = winner;
    keys[existingIdx] = findingDedupKey(winner);
    logFn(`${dimension}: merged ${dropped.id} into ${winner.id}${raised ? `, severity raised to ${winner.severity}` : ""}`);
  }
  return survivors;
}

function dimensionFileName(dim) {
  const numbers = {
    architecture: 1, security: 2, performance: 3, code_quality: 4, seo: 5, a11y: 6,
    typography: 7, ui_design: 8, ux: 9, animation: 10, docs_sync: 11, copy: 12, privacy: 13,
    payments: 14
  };
  const slugs = {
    architecture: 'architecture', security: 'security', performance: 'performance',
    code_quality: 'code-quality', seo: 'seo', a11y: 'a11y', typography: 'typography',
    ui_design: 'ui-design', ux: 'ux', animation: 'animation', docs_sync: 'docs-sync',
    copy: 'copy', privacy: 'privacy', payments: 'payments'
  };
  return `${numbers[dim]}-${slugs[dim]}.md`;
}

// Entry point: this script body IS the run, invoked by the Workflow tool with
// `agent`, `parallel`, `log`, `args` already in scope as globals.
// args: { repoRoot, scope: 'diff'|'repo', files, dimensions, effort, promptDir, guidelinesDir,
//         guidelines (flat TSV list, verbatim from match-guidelines.sh), dimensionDoc,
//         floorFiles (optional, object keyed by dimension id, e.g. { security: [...] }): the
//         content-based scout floor, precomputed by audit/bin/compute-floor.mjs from
//         audit/floor-signals.json since find.js has no filesystem access and no longer reads
//         scope-file content at all — the scout and specialist subagents read the repo
//         themselves. A dimension present as a key (even with an empty array) had its floor
//         computed; a dimension absent from floorFiles simply falls back to the scout for that
//         dimension and is reported under degradedDimensions,
//         dimensionFiles (optional, object keyed by dimension id, e.g. { payments: [...] });
//         narrow intent ONLY: a dimension-specific surface that is deliberately outside the
//         shared diff/repo scope (the original and still only real case is `payments` over the
//         precomputed Stripe surface). A dimension listed here scouts that file list wherever
//         the pipeline would otherwise use ctx.files; every other dimension keeps using
//         args.files unchanged. It is never a cheaper substitute for args.files in general —
//         see the args.files/dimensionFiles guard below, which throws on exactly that misuse,
//         dimensionContext (optional, object keyed by dimension id, e.g.
//         { payments: 'STRIPE_MODE=cashier,sdk' }); a dimension listed here gets that
//         string appended to its specialist briefing as its own line, never mixed into
//         MATCHED_GUIDELINES }
if (args.dimensions !== undefined && (!Array.isArray(args.dimensions) ||
  args.dimensions.some((dimension) => !ALL_DIMENSIONS.includes(dimension)))) {
  throw new Error('args.dimensions must be an array of supported dimension ids');
}
const dimensions = (args.dimensions && args.dimensions.length ? args.dimensions : ALL_DIMENSIONS);

const floorFiles = args.floorFiles || {};
const dimensionFiles = args.dimensionFiles || {};
// Hard guard against the exact misuse dimensionFiles is not for: routing every dimension
// through dimensionFiles to skip the shared scope entirely. That silently starves every
// dimension's content floor (computeFloorFiles returns nothing to add back), so scouts run
// with no deterministic floor and a scout that finds nothing ends its dimension as `skipped`.
// Fail loudly here instead.
if ((!args.files || args.files.length === 0) && Object.keys(dimensionFiles).length > 0) {
  throw new Error('args.dimensionFiles is for a dimension-specific surface outside the shared ' +
    'scope (e.g. payments/STRIPE_FILES), never a replacement for args.files. ' +
    'args.files is empty/absent while args.dimensionFiles is not.');
}

const ctx = {
  repoRoot: args.repoRoot,
  scope: args.scope,
  files: args.files || [],
  dimensionFiles,
  dimensionContext: args.dimensionContext || {},
  promptDir: args.promptDir,
  guidelinesDir: args.guidelinesDir || '',
  guidelines: args.guidelines || '',
  floorFiles,
  dimensionDoc: args.dimensionDoc || Object.fromEntries(
    ALL_DIMENSIONS.map((d) => [d, `${args.promptDir}/${dimensionFileName(d)}`])
  )
};

// Descending by (approximate) file count so large dimensions start first
// (Konzurrenz-Rechnung, Schritt 4): the workflow tool caps at 16 concurrent
// agents, so starting big dimensions first avoids them running alone at the
// end. The real count isn't known before the scout runs, so this uses the
// deterministic floor-file count as a proxy — cheap to compute up front. A
// dimension whose scope files carry no content (dimensionFiles-only, e.g.
// payments) always computes a floor of 0 regardless of true size, so it
// falls back to its raw scope-file count instead of sorting last.
// Same pass also flags a dimension as degraded when it is absent from
// args.floorFiles entirely: compute-floor.mjs never ran for it (or the
// caller omitted it), so computeFloorFiles has nothing to compute a content
// floor from and the dimension's scout ran with no deterministic floor (see
// the guard above). compute-floor.mjs always emits a key, possibly empty,
// for every requested dimension it was given, so key absence means "never
// computed", not "computed, no match".
const dimMeta = dimensions.map((d) => {
  const scopeFiles = scopeFilesFor(ctx, d);
  const floorCount = computeFloorFiles(d, scopeFiles, ctx.floorFiles, log).length;
  const floorComputed = Object.prototype.hasOwnProperty.call(floorFiles, d);
  const degraded = scopeFiles.length > 0 && !floorComputed;
  if (degraded) {
    log(`${d}: absent from args.floorFiles (${scopeFiles.length} scope file(s)), ran without a deterministic content floor`);
  }
  return { d, floorCount: floorCount === 0 && !floorComputed ? scopeFiles.length : floorCount, degraded };
});
const floorCountByDim = Object.fromEntries(dimMeta.map(({ d, floorCount }) => [d, floorCount]));
const degradedDimensions = dimMeta.filter(({ degraded }) => degraded).map(({ d }) => d);
const ordered = [...dimensions].sort((a, b) => floorCountByDim[b] - floorCountByDim[a]);

const results = {};
const skipped = [];

const dimensionResults = await parallel(ordered.map((dim) => async () => {
  const r = await runDimension(ctx, dim, agent, parallel, log);
  return [dim, r];
}));

for (const [index, entry] of dimensionResults.entries()) {
  const [dim, r] = entry || [ordered[index], {
    status: 'incomplete', files: [], chunks: 0, findings: [], verdicts: [],
    uncovered: ['dimension:failed'], unverified: [], unrefuted: []
  }];
  results[dim] = r;
  if (r.status === 'skipped') skipped.push(dim);
}

return {
  status: Object.values(results).some((r) => r.status === 'incomplete') ? 'incomplete' : 'complete',
  dimensions: results,
  skipped,
  degradedDimensions
};
