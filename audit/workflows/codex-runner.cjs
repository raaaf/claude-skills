#!/usr/bin/env node
'use strict';

// Disk bridge for the two bundled audit programs. It never starts a model or shell.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const clone = (value) => JSON.parse(JSON.stringify(value));
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
function atomic(file, value) {
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value, null, 2));
  fs.renameSync(temp, file);
}
function safeFile(root, name) {
  if (typeof name !== 'string' || !name || path.isAbsolute(name) || name.split(/[\\/]/).some((p) => p === '..' || /^\.env(?:\.|$)/.test(p))) {
    throw new Error(`Unsafe scope path: ${name}`);
  }
  const file = fs.realpathSync(path.resolve(root, name));
  const relative = path.relative(root, file);
  if (relative.startsWith(`..${path.sep}`) || relative === '..' || path.isAbsolute(relative) || relative.split(path.sep).some((p) => /^\.env(?:\.|$)/.test(p))) {
    throw new Error(`Scope path escapes root or resolves to an environment file: ${name}`);
  }
  if (!fs.statSync(file).isFile()) throw new Error(`Not a file: ${name}`);
  return file;
}
function scopeSnapshot(root, names) {
  return Object.fromEntries(names.map((name) => [name, hash(fs.readFileSync(safeFile(root, name)))]));
}
function documentSnapshot(root) {
  const result = {};
  function walk(folder) {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (/^\.env(?:\.|$)/.test(entry.name)) throw new Error('Environment files are not allowed in prompt directories');
      const file = path.join(folder, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`Symlink in prompt directory: ${file}`);
      if (entry.isDirectory()) walk(file);
      else if (entry.isFile()) result[path.relative(root, file)] = fs.readFileSync(file, 'utf8');
    }
  }
  walk(root);
  return result;
}
function checkSchema(schema) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) throw new Error('Invalid schema');
  const supported = ['type', 'enum', 'required', 'properties', 'items'];
  for (const key of Object.keys(schema)) if (!supported.includes(key)) throw new Error(`Unsupported schema constraint: ${key}`);
  if (!['object', 'array', 'string', 'integer', 'number', 'boolean', 'null'].includes(schema.type)) throw new Error(`Unsupported schema type: ${schema.type}`);
  if (schema.enum && (!Array.isArray(schema.enum) || !schema.enum.length)) throw new Error('Invalid schema enum');
  if (schema.required && (!Array.isArray(schema.required) || schema.required.some((key) => typeof key !== 'string'))) throw new Error('Invalid schema required');
  if (schema.properties) {
    if (schema.type !== 'object' || typeof schema.properties !== 'object' || Array.isArray(schema.properties)) throw new Error('Invalid schema properties');
    Object.values(schema.properties).forEach(checkSchema);
  }
  if (schema.items) checkSchema(schema.items);
}
function validate(value, schema, at = '$') {
  checkSchema(schema);
  const valid = schema.type === 'object' ? value !== null && typeof value === 'object' && !Array.isArray(value)
    : schema.type === 'array' ? Array.isArray(value)
    : schema.type === 'integer' ? Number.isInteger(value)
    : schema.type === 'null' ? value === null
    : typeof value === schema.type && (schema.type !== 'number' || Number.isFinite(value));
  if (!valid) throw new Error(`${at}: expected ${schema.type}`);
  if (schema.enum && !schema.enum.some((entry) => canonical(entry) === canonical(value))) throw new Error(`${at}: value outside enum`);
  if (schema.type === 'object') {
    for (const key of schema.required || []) if (!Object.hasOwn(value, key)) throw new Error(`${at}.${key}: required`);
    for (const [key, child] of Object.entries(schema.properties || {})) if (Object.hasOwn(value, key)) validate(value[key], child, `${at}.${key}`);
  }
  if (schema.type === 'array' && schema.items) value.forEach((item, i) => validate(item, schema.items, `${at}[${i}]`));
  return value;
}
function init(kind, argsFile, directory) {
  if (!['find', 'fix'].includes(kind)) throw new Error('Expected find or fix');
  const args = read(argsFile);
  args.repoRoot = fs.realpathSync(args.repoRoot);
  const names = kind === 'find' ? args.files : args.fixes?.map((fix) => fix.file);
  if (!Array.isArray(names)) throw new Error('Expected files array or fixes array');
  const inputs = scopeSnapshot(args.repoRoot, names);
  const runDir = path.resolve(directory);
  if (fs.existsSync(runDir)) throw new Error('Run directory already exists; resume with step');
  const sourcePath = path.join(__dirname, `${kind}.js`);
  const source = fs.readFileSync(sourcePath, 'utf8');
  args.promptDir = fs.realpathSync(args.promptDir || path.join(__dirname, '../agents'));
  if (args.guidelinesDir) args.guidelinesDir = fs.realpathSync(args.guidelinesDir);
  const documents = {};
  for (const root of [args.promptDir, args.guidelinesDir].filter(Boolean)) documents[root] = documentSnapshot(root);
  for (const file of Object.values(args.dimensionDoc || {})) {
    if (!Object.keys(documents).some((root) => path.resolve(file).startsWith(`${root}${path.sep}`))) {
      throw new Error('dimensionDoc must be inside the snapshotted prompt or guideline directory');
    }
  }
  delete args.fileContents;
  if (kind === 'find') args.fileContents = Object.fromEntries(names.map((name) => [name, fs.readFileSync(safeFile(args.repoRoot, name), 'utf8')]));
  fs.mkdirSync(runDir, { recursive: true });
  fs.mkdirSync(path.join(runDir, 'requests'));
  fs.writeFileSync(path.join(runDir, 'source.js'), source);
  atomic(path.join(runDir, 'args.json'), args);
  atomic(path.join(runDir, 'documents.json'), documents);
  const fingerprint = hash(canonical({ kind, args, source, documents }));
  const state = { version: 1, kind, sourcePath, sourceHash: hash(source), argsHash: hash(canonical(args)), documentsHash: hash(canonical(documents)), fingerprint, inputs, jobs: {} };
  atomic(path.join(runDir, 'state.json'), state);
  return { status: 'initialized', runDir, fileCount: names.length, cost: { status: 'unavailable', usd: null } };
}
function checkDrift(runDir, state, args) {
  if (hash(fs.readFileSync(state.sourcePath, 'utf8')) !== state.sourceHash || hash(fs.readFileSync(path.join(runDir, 'source.js'), 'utf8')) !== state.sourceHash) throw new Error('Workflow source drift; start a new run');
  if (hash(canonical(args)) !== state.argsHash) throw new Error('Run arguments drift');
  const documents = read(path.join(runDir, 'documents.json'));
  if (hash(canonical(documents)) !== state.documentsHash) throw new Error('Prompt snapshot drift');
  for (const [root, snapshot] of Object.entries(documents)) if (canonical(documentSnapshot(root)) !== canonical(snapshot)) throw new Error(`Prompt/guideline drift: ${root}`);
  const activeFixes = new Set(state.kind === 'fix' ? Object.values(state.jobs).filter((j) => j.status === 'pending' && j.options.phase === 'Fix').map((j) => j.fixFile) : []);
  const current = scopeSnapshot(args.repoRoot, Object.keys(state.inputs));
  for (const [name, digest] of Object.entries(current)) if (digest !== state.inputs[name] && !activeFixes.has(name)) throw new Error(`Scope content drift: ${name}`);
}
function incomplete(value) {
  if (!value || typeof value !== 'object') return false;
  return value.status === 'incomplete' || value.complete === false || Object.values(value).some(incomplete);
}
function codexDispatch(options) {
  const models = { sonnet: 'gpt-5.6-sol', opus: 'gpt-6-astra' };
  if (!Object.hasOwn(models, options.model)) throw new Error(`Unknown Codex model mapping: ${String(options.model)}`);
  const model = models[options.model];
  return {
    model,
    fork_turns: 'none',
    agent_type: options.agentType === 'Explore' ? 'explorer' : options.agentType,
  };
}
async function step(runDir, state) {
  const args = read(path.join(runDir, 'args.json'));
  checkDrift(runDir, state, args);
  const pending = new Set();
  const logs = [];
  const agent = (prompt, options) => {
    checkSchema(options.schema);
    const id = hash(canonical({ fingerprint: state.fingerprint, prompt, options }));
    let job = state.jobs[id];
    if (!job) {
      job = { id, prompt, options: clone(options), status: 'pending' };
      if (state.kind === 'fix' && options.phase === 'Fix') {
        job.fixFile = args.fixes.find((fix) => prompt.includes(`finding below in ${fix.file}.`))?.file;
        if (!job.fixFile) throw new Error('Unable to associate fixer with its authorized file');
      }
      state.jobs[id] = job;
      atomic(path.join(runDir, 'requests', `${id}.json`), { id, prompt, options, codex: codexDispatch(options) });
    }
    if (job.status === 'complete') return Promise.resolve(clone(validate(job.result, options.schema)));
    if (job.status === 'failed') return Promise.resolve(null);
    pending.add(id);
    return new Promise(() => {});
  };
  let output;
  let finished = false;
  let error;
  const source = fs.readFileSync(path.join(runDir, 'source.js'), 'utf8');
  if (!source.startsWith('export const meta = ')) throw new Error('Invalid bundled workflow header');
  const run = new AsyncFunction('agent', 'parallel', 'log', 'args', source.replace(/^export const meta = /, 'const meta = '));
  // Pending agents deliberately remain unresolved. One event-loop turn drains all
  // cached continuations and discovers the full next frontier without a model call.
  run(agent, (thunks) => Promise.all(thunks.map((fn) => fn())), (line) => logs.push(String(line)), clone(args))
    .then((result) => { output = result; finished = true; }, (cause) => { error = cause; });
  await new Promise(setImmediate);
  if (error) throw error;
  if (!finished && !pending.size) throw new Error('Workflow stalled without a pending agent');
  const failed = Object.values(state.jobs).filter((j) => j.status === 'failed').map(({ id, reason }) => ({ id, reason }));
  const status = !finished ? 'pending' : failed.length || incomplete(output) ? 'incomplete' : 'complete';
  const outputPath = finished ? path.join(runDir, 'output.json') : null;
  if (finished) atomic(outputPath, output);
  state.status = status;
  atomic(path.join(runDir, 'state.json'), state);
  atomic(path.join(runDir, 'progress.json'), { status, logs });
  return { status, pending: [...pending].map((id) => ({ id, requestPath: path.join(runDir, 'requests', `${id}.json`), phase: state.jobs[id].options.phase, agentType: state.jobs[id].options.agentType, ...codexDispatch(state.jobs[id].options), ...(state.jobs[id].nativeWorkerId ? { nativeWorkerId: state.jobs[id].nativeWorkerId } : {}) })), failed, outputPath, cost: { status: 'unavailable', usd: null } };
}
function bind(runDir, state, id, nativeWorkerId) {
  const job = state.jobs[id];
  if (!job) throw new Error('Unknown job ID');
  if (job.status !== 'pending') throw new Error(`Job is ${job.status}; cannot bind a worker`);
  if (!nativeWorkerId || !nativeWorkerId.trim()) throw new Error('Native worker ID required');
  if (job.nativeWorkerId && job.nativeWorkerId !== nativeWorkerId) throw new Error('Job already bound; recover the existing worker before further action');
  job.nativeWorkerId = nativeWorkerId;
  atomic(path.join(runDir, 'state.json'), state);
  return { id, status: job.status, nativeWorkerId };
}
function respond(runDir, state, command, id, reply) {
  const job = state.jobs[id];
  if (!job) throw new Error('Unknown job ID');
  if (job.status !== 'pending') throw new Error(`Job is ${job.status}; cached responses cannot be overwritten`);
  if (command === 'submit') {
    const result = validate(read(reply), job.options.schema);
    const args = read(path.join(runDir, 'args.json'));
    checkDrift(runDir, state, args);
    job.result = clone(result);
    if (state.kind === 'fix' && job.options.phase === 'Fix') {
      if (result.files.some((file) => file !== job.fixFile)) throw new Error('Fixer reported a file outside its authorized scope');
      state.inputs[job.fixFile] = hash(fs.readFileSync(safeFile(args.repoRoot, job.fixFile)));
    }
    job.status = 'complete';
  } else {
    if (!reply || !reply.trim()) throw new Error('Explicit failure reason required');
    if (state.kind === 'fix' && job.options.phase === 'Fix') {
      const args = read(path.join(runDir, 'args.json'));
      checkDrift(runDir, state, args);
      state.inputs[job.fixFile] = hash(fs.readFileSync(safeFile(args.repoRoot, job.fixFile)));
    }
    job.status = 'failed';
    job.reason = reply;
  }
  atomic(path.join(runDir, 'state.json'), state);
  return { id, status: job.status };
}
async function main(argv) {
  const [command, ...rest] = argv;
  if (command === 'init' && rest.length === 3) return init(...rest);
  if (!['step', 'submit', 'fail', 'bind'].includes(command) || rest.length !== (command === 'step' ? 1 : 3)) throw new Error('Usage: init <find|fix> <args.json> <run-dir> | step <run-dir> | submit <run-dir> <job-id> <response.json> | fail <run-dir> <job-id> <reason> | bind <run-dir> <job-id> <native-worker-id>');
  const runDir = path.resolve(rest[0]);
  const lock = path.join(runDir, '.lock');
  try { fs.mkdirSync(lock); } catch { throw new Error('Run is busy or has a stale .lock directory'); }
  try {
    const state = read(path.join(runDir, 'state.json'));
    return command === 'step' ? await step(runDir, state) : command === 'bind' ? bind(runDir, state, rest[1], rest[2]) : respond(runDir, state, command, rest[1], rest[2]);
  } finally { fs.rmdirSync(lock); }
}
module.exports = { main, validate, safeFile };
if (require.main === module) main(process.argv.slice(2)).then((result) => process.stdout.write(`${JSON.stringify(result)}\n`)).catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
