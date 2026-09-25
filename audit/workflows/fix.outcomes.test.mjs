// Pins the per-finding outcome bookkeeping in fix.js.
//
// fix.js is a workflow script: its body runs on import, so classifyOutcomes cannot
// be imported and called directly. This test therefore slices the function out of
// the source verbatim and runs it with `new Function`, the same extraction pattern
// verifier-gate.test.mjs uses for find.js. That keeps the test honest (it executes
// the shipped code, not a copy) at the cost of two string markers: if the function
// moves, the assertions below fail loudly rather than silently testing nothing.
//
// What it protects: every finding a fixer was assigned must resolve to FIXED,
// DISCARDED with a non-blank reason, or count as unresolved. A DISCARDED with a
// blank reason and a missing outcome entry must not silently pass as done. Decided
// 2026-09-25: severity plays no part, a Minor gets the same treatment as a Critical.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(path.join(here, 'fix.js'), 'utf8');

const START = 'function classifyOutcomes(findings, fix) {';
const END = '\n}';

function classifyOutcomesFn() {
  const start = src.indexOf(START);
  assert.ok(start > 0, `marker not found in fix.js: ${START}`);
  const end = src.indexOf(END, start);
  assert.ok(end > start, `end marker not found in fix.js after classifyOutcomes`);
  const body = src.slice(start, end + END.length);
  const fn = new Function(`${body}\nreturn classifyOutcomes;`);
  return fn();
}

const classifyOutcomes = classifyOutcomesFn();
const finding = (id) => ({ id });

test('a DISCARDED outcome with a reason lands in discarded, not unresolved', () => {
  const result = classifyOutcomes(
    [finding('a')],
    { outcomes: [{ id: 'a', result: 'DISCARDED', reason: 'not present at app/Foo.php:10' }] }
  );

  assert.deepEqual(result.discarded, [{ id: 'a', reason: 'not present at app/Foo.php:10' }]);
  assert.deepEqual(result.unresolved, []);
});

test('a DISCARDED outcome with a blank reason lands in unresolved', () => {
  const result = classifyOutcomes(
    [finding('a')],
    { outcomes: [{ id: 'a', result: 'DISCARDED', reason: '  ' }] }
  );

  assert.deepEqual(result.unresolved, ['a']);
  assert.deepEqual(result.discarded, []);
});

test('a finding id with no outcome entry lands in unresolved', () => {
  const result = classifyOutcomes(
    [finding('a'), finding('b')],
    { outcomes: [{ id: 'a', result: 'FIXED' }] }
  );

  assert.deepEqual(result.unresolved, ['b']);
  assert.deepEqual(result.discarded, []);
});
