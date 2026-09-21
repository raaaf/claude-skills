// Bounded TypeSafe Jev router for the audit file scouts.
//
// This helper sends relative paths and routing metadata by default. Bounded code
// context is an explicit opt-in. It never changes audit selection or decides
// correctness.
// Usage:
//   node compute-jev-routes.mjs REPO_ROOT off|shadow|assist|prune DIM1,DIM2,... [DIMENSION_FILES_JSON] [diff|repo] [paths|code] < file-list.txt

import { closeSync, lstatSync, mkdirSync, openSync, readFileSync, readSync, realpathSync, renameSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, relative, resolve, sep } from 'node:path';
import https from 'node:https';

export const ALL_DIMENSIONS = [
  'architecture', 'security', 'performance', 'code_quality', 'seo', 'a11y',
  'typography', 'ui_design', 'ux', 'animation', 'docs_sync', 'copy', 'privacy',
  'payments'
];
export const MAX_CANDIDATES = 64;
export const MAX_CODE_FILE_BYTES = 4096;
export const MAX_CODE_TOTAL_BYTES = 16384;
const API_URL = 'https://api.typesafe.ai/v1/systemone';
const CODE_DIMENSIONS = new Set(['security', 'performance', 'code_quality', 'privacy', 'seo', 'a11y', 'typography', 'ui_design', 'ux', 'animation', 'docs_sync', 'copy']);
// docs_sync is low-risk but cluster-only in find.js, so it is deliberately not
// pruned by this file-scout policy.
export const PRUNE_DIMENSIONS = new Set(['seo', 'a11y', 'typography', 'ui_design', 'ux', 'animation', 'copy']);
const CODE_DENY_RE = /(^|\/)(\.env(?:\.|$)|credentials?(?:\.|$)|secrets?(?:\.|$)|id_rsa(?:\.|$)|.*\.(pem|key|p12|pfx))$/i;
const SECRET_RE = /(-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]+|\bAKIA[0-9A-Z]{16}\b|(?:api[_-]?key|secret|token|password)\s*[:=]\s*['"][^'"]{8,}['"])/i;
const RUBRICS = {
  security: 'Concrete triggers only: untrusted input reaching SQL, shell, HTML, URL fetch, or deserialization; missing auth or capability guards; unsafe secret, token, upload, CSP, proxy, or prompt-tool handling. Existing validation, parameterized SQL, escaping, and auth guards remain security-relevant evidence.',
  performance: 'Concrete triggers only: N+1 or unbounded reads, repeated expensive work, missing transactions or locks, unbounded collections, repeated API calls, per-render allocation, main-thread blocking, or missed pagination/concurrency.',
  code_quality: 'Concrete triggers only: redundant or derivable state, parameter or state sprawl, structural copy-paste, hardcoded user-facing strings outside translation or component props, dead exports or parameters, leaky or stringly abstractions, and swallowed errors that coerce success.',
  privacy: 'Concrete triggers only: personal data, identifiers, IP addresses, tracking, cookies or storage, third-party embeds, analytics, logging, or external form data flows, especially where consent, retention, redaction, or a legal basis is absent.',
  seo: 'Concrete triggers only: crawlable routes, metadata, canonical or alternate links, robots or sitemap behavior, structured data, and indexability changes.',
  a11y: 'Concrete triggers only: interactive controls, forms, semantic structure, keyboard behavior, focus management, labels, contrast, live regions, or accessible names.',
  typography: 'Concrete triggers only: font loading, type tokens, readable text hierarchy, line length, responsive text behavior, or locale-sensitive typography.',
  ui_design: 'Concrete triggers only: visual components, layout, responsive states, design tokens, color, spacing, icons, or component variants.',
  ux: 'Concrete triggers only: user flows, navigation, loading or error states, destructive actions, feedback, form completion, or mobile interaction.',
  animation: 'Concrete triggers only: transitions, motion preferences, animation performance, animation state, or animated interactive elements.',
  docs_sync: 'Concrete triggers only: user-facing documentation, setup, API or configuration references, changelog, or claims coupled to implementation behavior.',
  copy: 'Concrete triggers only: user-facing strings, translation messages, labels, instructions, errors, empty states, or conversion copy.'
};

function fallback(reason, extra = {}, mode = 'shadow') {
  return { mode, status: 'fallback', reason, routes: [], usage: null, latencyMs: null, ...extra };
}

function readStdin() {
  try { return readFileSync(0, 'utf8'); } catch { return ''; }
}

export function validateInput({ repoRoot, mode, dimensions, files, dimensionFiles = {} }) {
  if (!['off', 'shadow', 'assist', 'prune'].includes(mode)) throw new Error('mode must be "off", "shadow", "assist", or "prune"');
  if (typeof repoRoot !== 'string' || !repoRoot.startsWith(sep)) throw new Error('repoRoot must be an absolute path');
  if (!Array.isArray(dimensions) || dimensions.length === 0 || dimensions.some((d) => !ALL_DIMENSIONS.includes(d))) {
    throw new Error('dimensions must be a non-empty array of supported dimension ids');
  }
  if (!Array.isArray(files) || files.some((path) => typeof path !== 'string')) throw new Error('files must be an array of paths');
  if (!dimensionFiles || typeof dimensionFiles !== 'object' || Array.isArray(dimensionFiles)) {
    throw new Error('dimensionFiles must be an object keyed by supported dimension ids');
  }
  const selectedDimensions = [...new Set(dimensions)];
  const rawCandidateCount = selectedDimensions.reduce((count, dimension) => {
    const paths = dimensionFiles[dimension] || files;
    return count + (Array.isArray(paths) ? new Set(paths).size : 0);
  }, 0);
  if (rawCandidateCount > MAX_CANDIDATES) throw new Error('scope_too_large');
  const root = resolve(repoRoot);
  const validatePath = (path) => {
    if (!path || path.startsWith('/') || path.includes('\\') || path.split('/').includes('..')) {
      throw new Error(`invalid relative path: ${path}`);
    }
    const full = resolve(root, path);
    const rel = relative(root, full);
    if (rel === '' || rel === '..' || rel.startsWith(`..${sep}`)) throw new Error(`out-of-scope path: ${path}`);
    let stat;
    try { stat = lstatSync(full); } catch { throw new Error(`out-of-scope path: ${path}`); }
    if (!stat.isFile()) throw new Error(`path is not a file: ${path}`);
    return path;
  };
  const shared = [...new Set(files.map(validatePath))];
  const surfaces = {};
  for (const [dimension, paths] of Object.entries(dimensionFiles)) {
    if (!ALL_DIMENSIONS.includes(dimension) || !Array.isArray(paths)) throw new Error(`invalid dimensionFiles entry: ${dimension}`);
    surfaces[dimension] = [...new Set(paths.map(validatePath))];
  }
  return { mode, dimensions: selectedDimensions, files: shared, dimensionFiles: surfaces };
}

export function buildCandidates(input) {
  const candidates = [];
  for (const dimension of input.dimensions) {
    const paths = input.dimensionFiles[dimension] || input.files;
    for (const path of paths) {
      if (candidates.length === MAX_CANDIDATES) return null;
      candidates.push({ id: `route-${String(candidates.length + 1).padStart(3, '0')}`, path, dimension });
    }
  }
  return candidates;
}

function contextSummary(files, reason = null) {
  return { mode: 'code', status: reason ? 'fallback' : 'ok', reason, byPath: Object.fromEntries(files.map((file) => [file.path, {
    complete: file.complete, truncated: file.truncated, missingDependencies: file.missingDependencies
  }])) };
}

function isInside(root, target) {
  const rel = relative(root, target);
  return rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !rel.startsWith('..');
}

function safeFile(root, path) {
  if (!path || path.startsWith('/') || path.includes('\\') || path.split('/').includes('..') || CODE_DENY_RE.test(path)) return { unsafe: true };
  const full = resolve(root, path);
  if (!isInside(root, full)) return { unsafe: true };
  let stat;
  try { stat = lstatSync(full); } catch { return { missing: true }; }
  if (!stat.isFile() || stat.isSymbolicLink()) return { unsafe: true };
  try {
    if (!isInside(root, realpathSync(full))) return { unsafe: true };
  } catch { return { missing: true }; }
  return { full, size: stat.size };
}

function directDependencies(root, path, content) {
  const specs = new Set();
  const re = /\b(?:from\s*|import\s*|require\s*\()\s*['"](\.[^'"]+)['"]/g;
  let match;
  while ((match = re.exec(content))) specs.add(match[1]);
  const missing = [];
  for (const spec of specs) {
    const imported = resolve(root, dirname(path), spec);
    // TypeScript projects commonly emit `.js` import specifiers while the
    // checked-out source is `.ts` or `.tsx`. Resolve the explicit specifier
    // first, then retry its extensionless source stem before declaring the
    // context incomplete.
    const base = imported.replace(/\.(?:c|m)?(?:js|jsx|ts|tsx)$/i, '');
    const options = [
      imported, base, `${base}.js`, `${base}.jsx`, `${base}.mjs`,
      `${base}.ts`, `${base}.tsx`, resolve(base, 'index.js'),
      resolve(base, 'index.ts'), resolve(base, 'index.tsx')
    ];
    if (!options.some((candidate) => safeFile(root, relative(root, candidate)).full)) missing.push(spec);
  }
  return missing;
}

function isBinary(buffer) {
  return buffer.subarray(0, 8000).includes(0);
}

function readPrefix(path, length) {
  const fd = openSync(path, 'r');
  try {
    const buffer = Buffer.alloc(length);
    const bytes = readSync(fd, buffer, 0, length, 0);
    return buffer.subarray(0, bytes);
  } finally {
    closeSync(fd);
  }
}

// Returns request-only source context plus a source-free summary. It does not
// follow symlinks and treats any credential-like path or literal as unsafe.
export function collectCodeContext({ repoRoot, files }) {
  if (typeof repoRoot !== 'string' || !repoRoot.startsWith(sep) || !Array.isArray(files)) {
    return { status: 'fallback', reason: 'invalid_context', requestContext: null, summary: { mode: 'code', status: 'fallback', reason: 'invalid_context', byPath: {} } };
  }
  let root;
  try { root = realpathSync(resolve(repoRoot)); } catch {
    return { status: 'fallback', reason: 'invalid_context', requestContext: null, summary: { mode: 'code', status: 'fallback', reason: 'invalid_context', byPath: {} } };
  }
  const requestFiles = [];
  let total = 0;
  for (const path of [...new Set(files)]) {
    const safe = safeFile(root, path);
    if (safe.unsafe) return { status: 'fallback', reason: 'unsafe_context', requestContext: null, summary: contextSummary(requestFiles, 'unsafe_context') };
    if (safe.missing) {
      requestFiles.push({ path, content: '', truncated: false, complete: false, missingDependencies: ['file_missing'] });
      continue;
    }
    const allowed = Math.min(MAX_CODE_FILE_BYTES, Math.max(0, MAX_CODE_TOTAL_BYTES - total));
    if (allowed === 0) {
      requestFiles.push({ path, content: '', truncated: true, complete: false, missingDependencies: ['request_limit'] });
      continue;
    }
    let buffer;
    try { buffer = readPrefix(safe.full, Math.min(safe.size, allowed)); } catch { requestFiles.push({ path, content: '', truncated: false, complete: false, missingDependencies: ['file_missing'] }); continue; }
    if (isBinary(buffer)) return { status: 'fallback', reason: 'unsafe_context', requestContext: null, summary: contextSummary(requestFiles, 'unsafe_context') };
    const slice = buffer.subarray(0, allowed);
    const content = slice.toString('utf8');
    if (SECRET_RE.test(content)) return { status: 'fallback', reason: 'unsafe_context', requestContext: null, summary: contextSummary(requestFiles, 'unsafe_context') };
    total += slice.length;
    const truncated = safe.size > slice.length;
    const missingDependencies = truncated ? ['dependency_check_incomplete'] : directDependencies(root, path, content);
    requestFiles.push({ path, content, truncated, complete: !truncated && missingDependencies.length === 0, missingDependencies });
  }
  return { status: 'ok', requestContext: { mode: 'code', files: requestFiles }, summary: contextSummary(requestFiles) };
}

export function buildRequest(candidates, scope, context = { mode: 'paths' }) {
  const questions = {};
  for (const candidate of candidates) {
    const rubric = RUBRICS[candidate.dimension] || 'This dimension is not supported by code-context routing. Choose uncertain.';
    questions[candidate.id] = {
      type: 'choice',
      instructions: `Shadow routing only. Candidate file=${candidate.path}; audit dimension=${candidate.dimension}. ${rubric} Is this file relevant for selecting audit scout coverage? Do not assess defects, correctness, or fixes.`,
      criteria: {
        relevant: 'The path is plausibly relevant to this audit dimension.',
        not_relevant: 'The path is not plausibly relevant to this audit dimension.',
        uncertain: 'The path alone is insufficient to decide relevance.'
      }
    };
  }
  const state = { purpose: 'audit_shadow_router', scope, selected_dimensions: [...new Set(candidates.map((c) => c.dimension))], candidate_count: candidates.length, context_mode: context.mode || 'paths' };
  if (context.mode === 'code') state.files = context.files.map((file) => ({ path: file.path, content: file.content, truncated: file.truncated, complete: file.complete, missing_dependencies: file.missingDependencies }));
  return { state, model: 'jev-latest', questions };
}

// Assist is deliberately a hint-only projection. It preserves every route and
// only groups the provider's choices for scout prioritization. The Workflow
// validates the paths again before placing this in a prompt.
export function buildAssistHints(routes, dimensions) {
  const order = { relevant: 0, uncertain: 1, not_relevant: 2 };
  return Object.fromEntries(dimensions.map((dimension) => {
    const scoped = (routes || []).filter((route) => route.dimension === dimension);
    const prioritizedPaths = [...scoped]
      .sort((a, b) => (order[a.choice] ?? 3) - (order[b.choice] ?? 3))
      .map((route) => route.path);
    return [dimension, {
      prioritizedPaths,
      relevantPaths: scoped.filter((route) => route.choice === 'relevant').map((route) => route.path),
      uncertainPaths: scoped.filter((route) => route.choice === 'uncertain').map((route) => route.path)
    }];
  }));
}

function postJson(payload, apiKey, requestFn = https.request) {
  return new Promise((resolvePromise, reject) => {
    let settled = false;
    let deadline;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      fn(value);
    };
    const body = JSON.stringify(payload);
    const request = requestFn(API_URL, {
      method: 'POST',
      headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) },
      timeout: 5000
    }, (response) => {
      let data = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        data += chunk;
        if (Buffer.byteLength(data) > 32768) request.destroy(new Error('response_too_large'));
      });
      response.on('error', (error) => finish(reject, error));
      response.on('aborted', () => finish(reject, new Error('response_aborted')));
      response.on('end', () => {
        if (response.statusCode >= 300 && response.statusCode < 400) return finish(reject, new Error('redirect_refused'));
        if (response.statusCode < 200 || response.statusCode >= 300) return finish(reject, new Error(`http_${response.statusCode}`));
        try { finish(resolvePromise, JSON.parse(data)); } catch { finish(reject, new Error('invalid_json')); }
      });
    });
    deadline = setTimeout(() => request.destroy(new Error('timeout')), 5000);
    request.on('error', (error) => finish(reject, error));
    request.write(body);
    request.end();
  });
}

export function parseResponse(response, candidates) {
  const answers = response && response.answers;
  if (!answers || typeof answers !== 'object' || Array.isArray(answers)) throw new Error('invalid_response');
  const expectedIds = new Set(candidates.map((candidate) => candidate.id));
  if (Object.keys(answers).some((id) => !expectedIds.has(id))) throw new Error('invalid_response');
  const routes = [];
  for (const candidate of candidates) {
    const answer = answers[candidate.id];
    if (!answer || !['relevant', 'not_relevant', 'uncertain'].includes(answer.choice)) throw new Error('partial_response');
    if (answer.confidence !== undefined && !Number.isFinite(answer.confidence)) throw new Error('invalid_response');
    if (answer.probabilities !== undefined && (!answer.probabilities || typeof answer.probabilities !== 'object' ||
      Array.isArray(answer.probabilities) || Object.values(answer.probabilities).some((value) => !Number.isFinite(value)))) throw new Error('invalid_response');
    routes.push({ id: candidate.id, path: candidate.path, dimension: candidate.dimension, choice: answer.choice,
      confidence: typeof answer.confidence === 'number' ? answer.confidence : null,
      probabilities: answer.probabilities && typeof answer.probabilities === 'object' ? answer.probabilities : null });
  }
  if (response.usage !== undefined && (!response.usage || typeof response.usage !== 'object' ||
    !Number.isFinite(response.usage.input_tokens) || !Number.isFinite(response.usage.output_tokens))) throw new Error('invalid_response');
  if (response.model !== undefined && typeof response.model !== 'string') throw new Error('invalid_response');
  return { routes, usage: response.usage ? { inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens } : null,
    model: response.model || null };
}

function pairKey(dimension, path) {
  return `${dimension}\u0000${path}`;
}

function cacheKey(input, candidates, requestContext) {
  return createHash('sha256').update(JSON.stringify({
    version: 1,
    repoRoot: input.repoRoot,
    scope: input.scope,
    dimensions: input.dimensions,
    files: input.files,
    dimensionFiles: input.dimensionFiles,
    candidates,
    requestContext
  })).digest('hex');
}

function readAssistCache(cacheDir, key, candidates) {
  if (!cacheDir || typeof cacheDir !== 'string' || !cacheDir.startsWith(sep)) return null;
  try {
    const cached = JSON.parse(readFileSync(resolve(cacheDir, `${key}.json`), 'utf8'));
    const expected = new Map(candidates.map((candidate) => [candidate.id, candidate]));
    const validRoutes = cached && Array.isArray(cached.routes) && cached.routes.length === candidates.length &&
      cached.routes.every((route) => {
        const candidate = expected.get(route && route.id);
        return candidate && route.path === candidate.path && route.dimension === candidate.dimension &&
          ['relevant', 'not_relevant', 'uncertain'].includes(route.choice);
      });
    return cached && cached.status === 'ok' && validRoutes ? cached : null;
  } catch { return null; }
}

function writeAssistCache(cacheDir, key, result) {
  if (!cacheDir || typeof cacheDir !== 'string' || !cacheDir.startsWith(sep)) return false;
  try {
    mkdirSync(cacheDir, { recursive: true, mode: 0o700 });
    const target = resolve(cacheDir, `${key}.json`);
    const temporary = `${target}.${process.pid}.tmp`;
    writeFileSync(temporary, JSON.stringify(result), { encoding: 'utf8', mode: 0o600 });
    renameSync(temporary, target);
    return true;
  } catch { return false; }
}

// Experimental, pure planning policy for the evaluator. It is intentionally
// not wired into find.js: a proposed non-relevant route is not production
// pruning until held-out evidence supports it.
export function planHybridRoutes({ candidates, routes, context, mandatoryPairs = [] }) {
  const proposedRoutes = [];
  const escalationPairs = [];
  const baselinePairs = [];
  const answers = new Map((routes || []).map((route) => [pairKey(route.dimension, route.path), route]));
  const mandatory = new Set(mandatoryPairs);
  const summary = context && context.summary && context.summary.byPath || {};
  for (const candidate of candidates || []) {
    const key = pairKey(candidate.dimension, candidate.path);
    if (!CODE_DIMENSIONS.has(candidate.dimension)) {
      baselinePairs.push({ ...candidate, reason: 'unsupported_dimension' });
      continue;
    }
    if (mandatory.has(key)) {
      proposedRoutes.push({ ...candidate, choice: 'relevant', reason: 'mandatory_floor' });
      continue;
    }
    const fileContext = summary[candidate.path];
    if (!context || context.status !== 'ok' || !fileContext || !fileContext.complete) {
      escalationPairs.push({ ...candidate, reason: 'context_incomplete' });
      continue;
    }
    const answer = answers.get(key);
    if (!answer) {
      escalationPairs.push({ ...candidate, reason: 'provider_unavailable' });
      continue;
    }
    if (answer.choice === 'uncertain') {
      escalationPairs.push({ ...candidate, reason: 'jev_uncertain' });
      continue;
    }
    if (!['relevant', 'not_relevant'].includes(answer.choice)) {
      escalationPairs.push({ ...candidate, reason: 'invalid_provider_choice' });
      continue;
    }
    proposedRoutes.push({ ...candidate, choice: answer.choice, reason: `jev_${answer.choice}_experimental` });
  }
  return { proposedRoutes, escalationPairs, baselinePairs };
}

// Pruning is deliberately narrower than the hybrid evaluator: only explicit
// low-risk dimensions, complete code context, a valid negative response, and
// no deterministic floor may remove a file from a file-scout prompt. The
// Workflow repeats these checks before it narrows any scope.
export function planPruneRoutes({ candidates, routes, context, mandatoryPairs = [] }) {
  const prunedPairs = [];
  const preservedPairs = [];
  const answers = new Map((routes || []).map((route) => [pairKey(route.dimension, route.path), route]));
  const mandatory = new Set(mandatoryPairs);
  const summary = context && context.summary && context.summary.byPath || {};
  for (const candidate of candidates || []) {
    const key = pairKey(candidate.dimension, candidate.path);
    if (!PRUNE_DIMENSIONS.has(candidate.dimension)) {
      preservedPairs.push({ ...candidate, reason: 'high_risk_dimension' });
      continue;
    }
    if (mandatory.has(key)) {
      preservedPairs.push({ ...candidate, reason: 'mandatory_floor' });
      continue;
    }
    const fileContext = summary[candidate.path];
    if (!context || context.status !== 'ok' || !fileContext || !fileContext.complete) {
      preservedPairs.push({ ...candidate, reason: 'context_incomplete' });
      continue;
    }
    const answer = answers.get(key);
    if (!answer) {
      preservedPairs.push({ ...candidate, reason: 'provider_unavailable' });
      continue;
    }
    if (answer.choice === 'not_relevant') {
      prunedPairs.push({ ...candidate, reason: 'jev_not_relevant' });
      continue;
    }
    preservedPairs.push({ ...candidate, reason: answer.choice === 'uncertain' ? 'jev_uncertain' : answer.choice === 'relevant' ? 'jev_relevant' : 'invalid_provider_choice' });
  }
  return { prunedPairs, preservedPairs };
}

export async function runShadow(rawInput, { apiKey = process.env.TYPESAFE_API_KEY, requestFn, now = () => Date.now() } = {}) {
  if (rawInput && rawInput.mode === 'off') return { mode: 'off', status: 'disabled', routes: [], usage: null, latencyMs: null, candidateCount: 0 };
  const requestedMode = rawInput && ['assist', 'prune'].includes(rawInput.mode) ? rawInput.mode : 'shadow';
  let input;
  try { input = validateInput(rawInput); } catch (error) { return fallback(error.message === 'scope_too_large' ? 'scope_too_large' : 'invalid_input', { detail: error.message }, requestedMode); }
  if (!apiKey) return fallback('missing_api_key', {}, requestedMode);
  const candidates = buildCandidates(input);
  if (candidates === null) return fallback('scope_too_large', { candidateCount: 0, maxCandidates: MAX_CANDIDATES }, requestedMode);
  if (candidates.length === 0) return fallback('empty_scope', { candidateCount: 0 }, requestedMode);
  const contextMode = rawInput.contextMode || 'paths';
  if (!['paths', 'code'].includes(contextMode)) return fallback('invalid_context_mode', { candidateCount: candidates.length }, requestedMode);
  const codeContext = contextMode === 'code' ? collectCodeContext({ repoRoot: input.repoRoot || rawInput.repoRoot, files: [...new Set(candidates.map((candidate) => candidate.path))] }) : null;
  const mandatoryPairs = Array.isArray(rawInput.mandatoryPairs) ? rawInput.mandatoryPairs.filter((pair) => typeof pair === 'string') : [];
  if (codeContext && codeContext.status !== 'ok') {
    return fallback(codeContext.reason, { candidateCount: candidates.length, context: codeContext.summary,
      assistHints: requestedMode === 'assist' ? {} : undefined,
      hybridPlan: planHybridRoutes({ candidates, routes: [], context: { status: 'fallback', summary: codeContext.summary }, mandatoryPairs }),
      prunePlan: requestedMode === 'prune' ? planPruneRoutes({ candidates, routes: [], context: { status: 'fallback', summary: codeContext.summary }, mandatoryPairs }) : undefined });
  }
  const requestContext = codeContext ? codeContext.requestContext : { mode: 'paths' };
  const plannerContext = codeContext ? { status: 'ok', summary: codeContext.summary } : { status: 'fallback', summary: { byPath: {} } };
  const cacheDir = rawInput.cacheDir && contextMode === 'code' ? rawInput.cacheDir : null;
  const request = buildRequest(candidates, rawInput.scope || 'unknown', requestContext);
  const key = cacheDir ? cacheKey(input, candidates, requestContext) : null;
  if (key) {
    const cached = readAssistCache(cacheDir, key, candidates);
    if (cached) return { ...cached, mode: requestedMode, cache: 'hit', latencyMs: 0 };
  }
  const started = now();
  try {
    const response = await postJson(request, apiKey, requestFn);
    const parsed = parseResponse(response, candidates);
    const result = { mode: requestedMode, status: 'ok', candidateCount: candidates.length, latencyMs: now() - started,
      context: codeContext ? codeContext.summary : { mode: 'paths', status: 'ok' },
      hybridPlan: planHybridRoutes({ candidates, routes: parsed.routes, context: plannerContext, mandatoryPairs }),
      ...(requestedMode === 'prune' ? { prunePlan: planPruneRoutes({ candidates, routes: parsed.routes, context: plannerContext, mandatoryPairs }) } : {}),
      ...(requestedMode === 'assist' ? { assistHints: buildAssistHints(parsed.routes, input.dimensions) } : {}), ...parsed, cache: key ? 'miss' : 'disabled' };
    if (key) writeAssistCache(cacheDir, key, result);
    return result;
  } catch (error) {
    const reason = error.message === 'partial_response' || error.message === 'invalid_response' || error.message === 'invalid_json' || error.message === 'redirect_refused'
      ? error.message : error.message === 'timeout' ? 'timeout' : 'network_error';
    return fallback(reason, { candidateCount: candidates.length, latencyMs: now() - started,
      context: codeContext ? codeContext.summary : { mode: 'paths', status: 'ok' },
      ...(requestedMode === 'assist' ? { assistHints: {} } : {}),
      hybridPlan: planHybridRoutes({ candidates, routes: [], context: plannerContext, mandatoryPairs }),
      ...(requestedMode === 'prune' ? { prunePlan: planPruneRoutes({ candidates, routes: [], context: plannerContext, mandatoryPairs }) } : {}) }, requestedMode);
  }
}

async function main() {
  const [repoRoot, mode, dimensionsArg, dimensionFilesArg = '{}', scope = 'unknown', contextMode = 'paths'] = process.argv.slice(2);
  let dimensionFiles;
  try { dimensionFiles = JSON.parse(dimensionFilesArg); } catch { process.stdout.write(JSON.stringify(fallback('invalid_input', { detail: 'dimensionFiles must be JSON' }))); return; }
  const result = await runShadow({ repoRoot, mode, scope, contextMode, dimensions: (dimensionsArg || '').split(',').filter(Boolean), files: readStdin().split('\n').filter(Boolean), dimensionFiles, cacheDir: process.env.JEV_ROUTER_CACHE_DIR });
  process.stdout.write(JSON.stringify(result));
}

// realpathSync on both sides: ~/.claude/skills is a symlink to the source checkout, and a plain
// resolve() of argv[1] never equalled import.meta.url through it, so main() silently never ran
// and every audit fell back to scope_too_large (2026-09-20).
if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(new URL(import.meta.url).pathname)) main();
