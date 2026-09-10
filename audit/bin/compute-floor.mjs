#!/usr/bin/env node
//
// compute-floor.mjs — content-based scout floor for the /audit and /full-audit
// find pipeline (audit/workflows/find.js).
//
// find.js runs inside the Workflow tool with no filesystem access, so it
// cannot read scope-file content itself; historically the orchestrator read
// every scope file with the Read tool and inlined the full text as
// args.fileContents so find.js could regex-match it. That inlining cost 104
// to 132 KB of orchestrator context in real repos and caused two sessions to
// bypass the pipeline outright (one refused to inline, one routed every
// dimension through dimensionFiles to dodge it, which starved every content
// floor). This script does the same regex matching, but in a Node process the
// orchestrator shells out to, reading files itself: only the resulting
// per-dimension path list crosses back into the orchestrator's context.
//
// Signals live in audit/floor-signals.json, the single source of truth for
// WHAT a floor matches — this script only decides WHERE that computation
// runs. Do not change a signal here or in the JSON without re-measuring
// recall (see floor-signals.json's _description and CLAUDE.md "The scout
// floor is content-based and calibrated").
//
// Usage:
//   node compute-floor.mjs REPO_ROOT DIM1,DIM2,... < file-list.txt
//
// REPO_ROOT: absolute path; each stdin line is resolved as REPO_ROOT/<path>.
// DIM1,DIM2,...: comma-separated dimension ids to compute a floor for. A
//   dimension with no entry in floor-signals.json (currently only
//   `architecture`) is still present in the output, as an empty array — this
//   lets a caller tell "no signal defined" apart from "helper never ran" by
//   checking key presence, which is what find.js's degradedDimensions
//   reporting relies on.
// stdin: newline-separated repo-relative file paths, the scope to scan.
//
// Output (stdout): {"<dimension>": ["<path>", ...], ...} for every requested
// dimension.
// Output (stderr): a count of files skipped as unreadable/binary, if any.
// An unreadable or binary file is skipped, never fatal.

import { readFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function isBinary(buffer) {
  const len = Math.min(buffer.length, 8000);
  for (let i = 0; i < len; i++) {
    if (buffer[i] === 0) return true;
  }
  return false;
}

function main() {
  const repoRoot = process.argv[2];
  const dimensionArg = process.argv[3];
  if (!repoRoot || !dimensionArg) {
    process.stderr.write('Usage: node compute-floor.mjs REPO_ROOT DIM1,DIM2,... < file-list.txt\n');
    process.exit(1);
  }
  const dimensions = dimensionArg.split(',').map((d) => d.trim()).filter(Boolean);

  const signalsPath = join(SCRIPT_DIR, '..', 'floor-signals.json');
  const signalsJson = JSON.parse(readFileSync(signalsPath, 'utf8'));
  const signalsByDimension = {};
  for (const [dim, entry] of Object.entries(signalsJson.dimensions || {})) {
    signalsByDimension[dim] = (entry.signals || []).map((s) => new RegExp(s.source, s.flags || ''));
  }

  const files = readStdin().split('\n').map((line) => line.trim()).filter(Boolean);

  const floor = {};
  for (const dim of dimensions) floor[dim] = [];

  let unreadable = 0;
  for (const path of files) {
    const dimsWithSignals = dimensions.filter((dim) => signalsByDimension[dim]);
    if (dimsWithSignals.length === 0) continue;
    let buffer;
    try {
      buffer = readFileSync(resolve(repoRoot, path));
    } catch {
      unreadable++;
      continue;
    }
    if (isBinary(buffer)) {
      unreadable++;
      continue;
    }
    const content = buffer.toString('utf8');
    for (const dim of dimsWithSignals) {
      if (signalsByDimension[dim].some((re) => re.test(content))) {
        floor[dim].push(path);
      }
    }
  }

  if (unreadable) {
    process.stderr.write(`compute-floor: skipped ${unreadable} of ${files.length} file(s) as unreadable/binary\n`);
  }

  process.stdout.write(JSON.stringify(floor));
}

main();
