// Pins chunkFilesForDimension (find.js), the Stage 2 function that decides how many file
// chunks -- and therefore how many specialist dispatches -- a dimension gets.
//
// find.js is a workflow script: its body runs on import, so chunkFilesForDimension cannot be
// imported and called directly. This test slices it out of the source verbatim, along with its
// one dependency (chunkByDirectory) and ALWAYS_CHUNKED_DIMENSIONS, and runs it with `new
// Function`, the same extraction pattern fix.outcomes.test.mjs uses for fix.js. That keeps the
// test honest (it executes the shipped code, not a copy) at the cost of marker strings: if a
// function moves or is renamed, the assertions below fail loudly rather than silently testing
// nothing.
//
// What it protects: on a SMALL diff, every dimension collapses to one unchunked chunk (one
// specialist call instead of one per 5-8-file chunk) -- except security/privacy/payments, which
// always keep chunkByDirectory's normal chunking. On anything above SMALL, chunking is
// unchanged for every dimension.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(path.join(here, 'find.js'), 'utf8');

function sliceBetween(startMarker, endMarker) {
  const start = src.indexOf(startMarker);
  assert.ok(start > 0, `start marker not found in find.js: ${startMarker}`);
  const end = src.indexOf(endMarker, start);
  assert.ok(end > start, `end marker not found in find.js after: ${startMarker}`);
  return src.slice(start, end + endMarker.length);
}

function loadChunkFilesForDimension() {
  const chunkByDirFn = sliceBetween('function chunkByDirectory(files) {', '\n}');
  const alwaysChunked = sliceBetween('const ALWAYS_CHUNKED_DIMENSIONS = [', '\n');
  const chunkFn = sliceBetween('function chunkFilesForDimension(dimension, files, sizeResult) {', '\n}');
  const body = [chunkByDirFn, alwaysChunked, chunkFn].join('\n');
  const fn = new Function(`${body}\nreturn chunkFilesForDimension;`);
  return fn();
}

const chunkFilesForDimension = loadChunkFilesForDimension();

// 20 files across enough directories that chunkByDirectory splits them into multiple chunks
// (each directory group here is 1 file, well below the 5-8-file merge threshold, so they get
// concatenated into 8-file chunks: 20 files -> 3 chunks of chunkByDirectory today).
const files20 = Array.from({ length: 20 }, (_, i) => `dir${i}/file.ts`);

test('SMALL + code_quality with 20 files: exactly one chunk', () => {
  const chunks = chunkFilesForDimension('code_quality', files20, 'SMALL');
  assert.equal(chunks.length, 1);
  assert.deepEqual(chunks[0], files20);
});

test('SMALL + security with 20 files: multiple chunks, same as today', () => {
  const chunks = chunkFilesForDimension('security', files20, 'SMALL');
  assert.ok(chunks.length > 1, `expected multiple chunks, got ${chunks.length}`);
});

test('SMALL + privacy / payments also stay chunked', () => {
  assert.ok(chunkFilesForDimension('privacy', files20, 'SMALL').length > 1);
  assert.ok(chunkFilesForDimension('payments', files20, 'SMALL').length > 1);
});

test('OK + code_quality: same chunks as chunkByDirectory today', () => {
  const chunked = chunkFilesForDimension('code_quality', files20, 'OK');
  assert.ok(chunked.length > 1, `expected multiple chunks, got ${chunked.length}`);
  const flat = chunked.flat();
  assert.deepEqual(flat.slice().sort(), files20.slice().sort());
});

test('SMALL with no files: no chunks, not one empty chunk', () => {
  assert.deepEqual(chunkFilesForDimension('code_quality', [], 'SMALL'), []);
});

test('this test fails if the always-chunked exception is removed', () => {
  // Regression guard: without ALWAYS_CHUNKED_DIMENSIONS, security would collapse to one
  // unchunked chunk on a SMALL diff, same as code_quality.
  const chunks = chunkFilesForDimension('security', files20, 'SMALL');
  assert.notEqual(chunks.length, 1, 'security collapsed to one chunk on a SMALL diff');
});
