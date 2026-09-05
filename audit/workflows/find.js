// audit/workflows/find.js
//
// Per-dimension find pipeline for /audit and /full-audit. Plain JavaScript, no
// TypeScript, no npm dependency, no Date.now(), no Math.random() (Konventionen,
// CLAUDE.md). Dispatched via the Workflow tool: `Workflow({ scriptPath: 'audit/workflows/find.js',
// args, resumeFromRunId })`.
//
// Contract this script relies on (audit/references/finding-schema.md,
// "Workflow-Kontrakt, geprueft am 2026-09-05"):
//   - agent(prompt, opts) with opts.agentType / opts.model / opts.schema returns the
//     schema-validated object directly (no JSON.parse needed).
//   - parallel(thunks) resolves every thunk; a thrown/aborted agent comes back as
//     null in its slot instead of rejecting the whole parallel() call.
//   - log(message) surfaces a line in the run's live progress (`/workflows`).
//   - resumeFromRunId replays completed agents from cache when script + args are
//     unchanged.
//
// This file must stay plain and side-effect-free until the exported `run`
// function is invoked by the Workflow tool.

import { warnIfNull } from './lib.js';

export const meta = {
  phases: ['Scout', 'Audit', 'Verify']
};

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

async function runFileScout(ctx, dimension, agent, log) {
  const promptDoc = `${ctx.promptDir}/scout-files.md`;
  const scopeFiles = ctx.files;
  const floorFiles = computeFloorFiles(dimension, scopeFiles);
  const result = await agent(
    `Read ${promptDoc} and execute the file-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(scopeFiles)}\nFLOOR_FILES=${JSON.stringify(floorFiles)}\n` +
    `SCOPE=${ctx.scope}`,
    { agentType: 'Explore', model: 'sonnet', schema: 'SCOUT_FILES_SCHEMA', phase: 'Scout' }
  );
  if (warnIfNull(log, result, `${dimension}: file scout returned null, using floor files only`)) {
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
    log(`${dimension}: scout omitted ${added.length} floor file(s), re-added: ${added.join(', ')}`);
  }
  return result.files;
}

async function runClusterScout(ctx, dimension, agent, log) {
  const promptDoc = `${ctx.promptDir}/scout-clusters.md`;
  const result = await agent(
    `Read ${promptDoc} and execute the cluster-scout task for DIMENSION=${dimension}.\n` +
    `SCOPE_FILES=${JSON.stringify(ctx.files)}`,
    { agentType: 'Explore', model: 'sonnet', schema: 'SCOUT_CLUSTERS_SCHEMA', phase: 'Scout' }
  );
  if (warnIfNull(log, result, `${dimension}: cluster scout returned null`)) return [];
  return result.clusters;
}

async function runDimension(ctx, dimension, agent, parallel, log) {
  // Stage 1: scout(s).
  let files = [];
  let clusters = [];
  if (CLUSTER_ONLY_DIMENSIONS.includes(dimension)) {
    clusters = await runClusterScout(ctx, dimension, agent, log);
  } else if (BOTH_SCOUTS_DIMENSIONS.includes(dimension)) {
    const [fileResult, clusterResult] = await parallel([
      () => runFileScout(ctx, dimension, agent, log),
      () => runClusterScout(ctx, dimension, agent, log)
    ]);
    files = fileResult || [];
    clusters = clusterResult || [];
  } else {
    files = await runFileScout(ctx, dimension, agent, log);
  }

  if (files.length === 0 && clusters.length === 0) {
    log(`${dimension}: skipped, no relevant files`);
    return { status: 'skipped', files: [], chunks: 0, findings: [], verdicts: [], uncovered: [] };
  }

  // Stage 2: chunking (code, not an agent).
  const filePaths = files.map((f) => f.path);
  const chunks = clusters.length
    ? clusters.map((c) => ({ kind: 'cluster', cluster: c }))
    : chunkByDirectory(filePaths).map((group) => ({ kind: 'files', files: group }));
  log(`${dimension}: scout ${filePaths.length || clusters.length} unit(s), ${chunks.length} chunk(s)`);
  if (chunks.length > 15) {
    log(`${dimension}: ${chunks.length} chunks, above the 15-chunk expectation`);
  }

  const guidelines = (ctx.guidelines && ctx.guidelines[dimension]) || [];
  const agentType = AGENT_TYPE_BY_DIMENSION[dimension];
  const dimDoc = ctx.dimensionDoc[dimension];

  // Stage 3: specialists, one per chunk, in parallel.
  const specialistResults = await parallel(chunks.map((c, i) => async () => {
    const briefing = c.kind === 'cluster'
      ? `CLUSTER=${JSON.stringify(c.cluster)}`
      : `FILES=${JSON.stringify(c.files)}`;
    const result = await agent(
      `Read ${ctx.promptDir}/prompt-template.md and ${dimDoc} and execute the specialist task ` +
      `for DIMENSION=${dimension}.\n${briefing}\nGUIDELINE_MATCHES=${JSON.stringify(guidelines)}\n` +
      `SCOPE=${ctx.scope}`,
      { agentType, model: 'sonnet', schema: 'FINDINGS_SCHEMA', phase: 'Audit' }
    );
    if (warnIfNull(log, result, `${dimension}: specialist for chunk ${i} returned null`)) return null;
    return result;
  }));
  const specialists = specialistResults.filter(Boolean);
  log(`${dimension}: ${specialists.length}/${chunks.length} specialists done`);

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
  const verifierResults = await parallel(verifierGroups.map((group) => async () => {
    const result = await agent(
      `Read ${ctx.promptDir}/finding-verifier.md and verify these findings.\n` +
      `FINDINGS=${JSON.stringify(group)}`,
      { agentType: 'code-reviewer', model: 'sonnet', schema: 'VERDICTS_SCHEMA', phase: 'Verify' }
    );
    if (warnIfNull(log, result, `${dimension}: a verifier group returned null (${group.length} findings uncovered)`)) return null;
    return result.verdicts;
  }));
  let verdicts = verifierResults.filter(Boolean).flat();

  // Stage 5: refuter, one per CONFIRMED Critical.
  const criticalConfirmed = verdicts.filter((v) => v.verdict === 'CONFIRMED' && v.severity === 'Critical');
  if (criticalConfirmed.length) {
    const refuterResults = await parallel(criticalConfirmed.map((v) => async () => {
      const finding = allFindings.find((f) => f.id === v.id);
      const refuterVerdict = await agent(
        `Read ${ctx.promptDir}/finding-verifier.md, section "Refuter". Try to refute this ` +
        `CONFIRMED Critical finding.\nFINDING=${JSON.stringify(finding)}\nVERDICT=${JSON.stringify(v)}`,
        { agentType: 'code-reviewer', model: 'opus', schema: 'VERDICTS_SCHEMA', phase: 'Verify' }
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

// Entry point invoked by the Workflow tool.
// args: { repoRoot, scope: 'diff'|'repo', files, dimensions, effort, promptDir, guidelines, dimensionDoc }
export async function run(args, { agent, parallel, log }) {
  const dimensions = (args.dimensions && args.dimensions.length ? args.dimensions : ALL_DIMENSIONS);

  const ctx = {
    repoRoot: args.repoRoot,
    scope: args.scope,
    files: args.files || [],
    promptDir: args.promptDir,
    guidelines: args.guidelines || {},
    dimensionDoc: args.dimensionDoc || Object.fromEntries(
      ALL_DIMENSIONS.map((d, i) => [d, `${args.promptDir}/${dimensionFileName(d)}`])
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
