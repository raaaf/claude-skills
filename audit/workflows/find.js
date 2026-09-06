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
  'Work only inside REPO_ROOT. Every path in this briefing is relative to REPO_ROOT; read files as ' +
  'REPO_ROOT/<path>. Do not use the current working directory, it may be a different repository.\n\n';

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
  copy: 'code-reviewer'
};

// Dimensions that use ONLY the cluster scout (no file scout).
const CLUSTER_ONLY_DIMENSIONS = ['architecture', 'docs_sync'];
// Dimensions that use BOTH scouts (results merge in Stage 2).
const BOTH_SCOUTS_DIMENSIONS = ['security'];

const ALL_DIMENSIONS = [
  'architecture', 'security', 'performance', 'code_quality', 'seo', 'a11y',
  'typography', 'ui_design', 'ux', 'animation', 'docs_sync', 'copy', 'privacy'
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

function computeFloorFiles(dimension, files) {
  return files.filter((f) => floorDimensionsForFile(f).includes(dimension));
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

async function runFileScout(ctx, dimension, agentFn, logFn) {
  const promptDoc = `${ctx.promptDir}/scout-files.md`;
  const scopeFiles = ctx.files;
  const floorFiles = computeFloorFiles(dimension, scopeFiles);
  const result = await agentFn(
    ROOT_HEADER +
    `Read ${promptDoc} and execute the file-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(scopeFiles)}\nFLOOR_FILES=${JSON.stringify(floorFiles)}\n` +
    `SCOPE=${ctx.scope}`,
    { agentType: 'Explore', model: 'sonnet', schema: SCOUT_FILES_SCHEMA, phase: 'Scout' }
  );
  if (warnIfNull(logFn, result, `${dimension}: file scout returned null, using floor files only`)) {
    return floorFiles.map((path) => ({ path, tag: 'floor', reason: 'scout unavailable' }));
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
  return result.files;
}

async function runClusterScout(ctx, dimension, agentFn, logFn) {
  const promptDoc = `${ctx.promptDir}/scout-clusters.md`;
  const result = await agentFn(
    ROOT_HEADER +
    `Read ${promptDoc} and execute the cluster-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(ctx.files)}`,
    { agentType: 'Explore', model: 'sonnet', schema: SCOUT_CLUSTERS_SCHEMA, phase: 'Scout' }
  );
  if (warnIfNull(logFn, result, `${dimension}: cluster scout returned null`)) return [];
  return result.clusters;
}

async function runDimension(ctx, dimension, agentFn, parallelFn, logFn) {
  // Stage 1: scout(s).
  let files = [];
  let clusters = [];
  if (CLUSTER_ONLY_DIMENSIONS.includes(dimension)) {
    clusters = await runClusterScout(ctx, dimension, agentFn, logFn);
  } else if (BOTH_SCOUTS_DIMENSIONS.includes(dimension)) {
    const [fileResult, clusterResult] = await parallelFn([
      () => runFileScout(ctx, dimension, agentFn, logFn),
      () => runClusterScout(ctx, dimension, agentFn, logFn)
    ]);
    files = fileResult || [];
    clusters = clusterResult || [];
  } else {
    files = await runFileScout(ctx, dimension, agentFn, logFn);
  }

  if (files.length === 0 && clusters.length === 0) {
    logFn(`${dimension}: skipped, no relevant files`);
    return { status: 'skipped', files: [], chunks: 0, findings: [], verdicts: [], uncovered: [] };
  }

  // Stage 2: chunking (code, not an agent).
  const filePaths = files.map((f) => f.path);
  // A cluster naming fewer than 2 files is not a cluster (scout-clusters.md
  // "at least two files"); drop it rather than dispatching a specialist that
  // sees a single file with no comparison to make.
  const droppedSingleFileClusters = clusters.filter((c) => !c.files || c.files.length < 2).length;
  clusters = clusters.filter((c) => c.files && c.files.length >= 2);
  if (droppedSingleFileClusters) {
    logFn(`${dimension}: dropped ${droppedSingleFileClusters} single-file cluster(s)`);
  }
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
    const result = await agentFn(
      ROOT_HEADER +
      `Read ${ctx.promptDir}/prompt-template.md and ${dimDoc} and execute the specialist task ` +
      `for DIMENSION=${dimension}.\nCHUNK_INDEX=${i}\n${briefing}\n` +
      `GUIDELINES_DIR=${ctx.guidelinesDir}\nMATCHED_GUIDELINES=${ctx.guidelines}\n` +
      `SCOPE=${ctx.scope}`,
      { agentType, model: 'sonnet', schema: FINDINGS_SCHEMA, phase: 'Audit' }
    );
    if (warnIfNull(logFn, result, `${dimension}: specialist for chunk ${i} returned null`)) return null;
    return result;
  }));
  const specialists = specialistResults.filter(Boolean);
  logFn(`${dimension}: ${specialists.length}/${chunks.length} specialists done`);

  const uncovered = [];
  chunks.forEach((c, i) => {
    if (!specialistResults[i]) {
      uncovered.push(c.kind === 'cluster' ? c.cluster.id : c.files.join(','));
    }
  });

  const allFindings = specialists.flatMap((s) => s.findings);

  if (allFindings.length === 0) {
    return { status: 'complete', files: filePaths, chunks: chunks.length, findings: [], verdicts: [], uncovered };
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
  let verdicts = verifierResults.filter(Boolean).flat();

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
      if (!r) return;
      const refuted = r.verdicts && r.verdicts[0];
      if (refuted && refuted.verdict === 'REFUTED') {
        const original = criticalConfirmed[i];
        original.severity = 'Important';
        original.disputed = true;
        original.reason = `${original.reason} | disputed by refuter: ${refuted.reason}`;
      }
    });
  }

  return {
    status: uncovered.length ? 'incomplete' : 'complete',
    files: filePaths,
    chunks: chunks.length,
    findings: allFindings,
    verdicts,
    uncovered
  };
}

function dimensionFileName(dim) {
  const numbers = {
    architecture: 1, security: 2, performance: 3, code_quality: 4, seo: 5, a11y: 6,
    typography: 7, ui_design: 8, ux: 9, animation: 10, docs_sync: 11, copy: 12, privacy: 13
  };
  const slugs = {
    architecture: 'architecture', security: 'security', performance: 'performance',
    code_quality: 'code-quality', seo: 'seo', a11y: 'a11y', typography: 'typography',
    ui_design: 'ui-design', ux: 'ux', animation: 'animation', docs_sync: 'docs-sync',
    copy: 'copy', privacy: 'privacy'
  };
  return `${numbers[dim]}-${slugs[dim]}.md`;
}

// Entry point: this script body IS the run, invoked by the Workflow tool with
// `agent`, `parallel`, `log`, `args` already in scope as globals.
// args: { repoRoot, scope: 'diff'|'repo', files, dimensions, effort, promptDir, guidelinesDir,
//         guidelines (flat TSV list, verbatim from match-guidelines.sh), dimensionDoc }
const dimensions = (args.dimensions && args.dimensions.length ? args.dimensions : ALL_DIMENSIONS);

const ctx = {
  repoRoot: args.repoRoot,
  scope: args.scope,
  files: args.files || [],
  promptDir: args.promptDir,
  guidelinesDir: args.guidelinesDir || '',
  guidelines: args.guidelines || '',
  dimensionDoc: args.dimensionDoc || Object.fromEntries(
    ALL_DIMENSIONS.map((d) => [d, `${args.promptDir}/${dimensionFileName(d)}`])
  )
};

// Descending by (approximate) file count so large dimensions start first
// (Konzurrenz-Rechnung, Schritt 4): the workflow tool caps at 16 concurrent
// agents, so starting big dimensions first avoids them running alone at the
// end. The real count isn't known before the scout runs, so this uses the
// deterministic floor-file count as a proxy — cheap to compute up front.
const floorCountByDim = Object.fromEntries(
  dimensions.map((d) => [d, computeFloorFiles(d, ctx.files).length])
);
const ordered = [...dimensions].sort((a, b) => floorCountByDim[b] - floorCountByDim[a]);

const results = {};
const skipped = [];

const dimensionResults = await parallel(ordered.map((dim) => async () => {
  const r = await runDimension(ctx, dim, agent, parallel, log);
  return [dim, r];
}));

for (const entry of dimensionResults) {
  if (!entry) continue;
  const [dim, r] = entry;
  results[dim] = r;
  if (r.status === 'skipped') skipped.push(dim);
}

return { dimensions: results, skipped };
