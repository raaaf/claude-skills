#!/usr/bin/env node
//
// minor-split.mjs: decides which non-REFUTED findings go to the fix wave and which Minors go
// to the per-repo backlog (rule decided 2026-10-01; 249 raw findings of one zeit audit were 224
// Minor, and fixing every one meant ~17 spec-executor rounds).
//
//   1. Critical and Important always go to the fix wave.
//   2. A Minor rides along only when EVERY file it names already receives a Critical/Important
//      fix in this wave (fix.js groups per file, so the same fixer handles it at little cost).
//   3. Every other Minor goes to the backlog.
//   4. A backlog entry whose file receives a fix in this wave is added to that file's fixes
//      (the orchestrator marks it verdict "UNCERTAIN": the fixer re-checks it against the code).
//
// Usage: node minor-split.mjs < input.json
//   input:  { "findings": [{id, severity, files: [{path, lines}], ...}],   (non-REFUTED only)
//             "backlog":  [{key, dimension, file, line, first_seen, description}] }
//   output: { "fix": [...findings], "ridealongBacklog": [...entries], "toBacklog": [...Minors] }

import { readFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function split({ findings = [], backlog = [] } = {}) {
  const paths = (f) => (Array.isArray(f.files) ? f.files.map((x) => x.path) : []);
  const major = findings.filter((f) => f.severity !== 'Minor');
  const fixFiles = new Set(major.flatMap(paths));
  const ridesAlong = (f) => {
    const p = paths(f);
    return p.length > 0 && p.every((x) => fixFiles.has(x));
  };
  const minors = findings.filter((f) => f.severity === 'Minor');
  const fix = [...major, ...minors.filter(ridesAlong)];
  const toBacklog = minors.filter((f) => !ridesAlong(f));
  const ridealongBacklog = backlog.filter((e) => fixFiles.has(e.file));
  return { fix, ridealongBacklog, toBacklog };
}

// import.meta.url is the realpath, argv[1] keeps a symlink (~/.claude/skills/audit), so resolve it.
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.stdout.write(JSON.stringify(split(JSON.parse(readFileSync(0, 'utf8') || '{}'))) + '\n');
}
