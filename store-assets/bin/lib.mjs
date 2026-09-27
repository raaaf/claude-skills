// Shared helpers for render.mjs and validate.mjs.
import { createHash } from 'node:crypto';

// SHA-256 of headline+subline, the `reviewed_hash` contract in
// references/config-schema.md ("Headline nach Freigabe geändert").
export function reviewedHash(headline, subline) {
  return createHash('sha256').update(headline + subline).digest('hex');
}

// Minimal `--key value` CLI parser shared by both bin scripts.
export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      out[argv[i].slice(2)] = argv[i + 1];
      i++;
    }
  }
  return out;
}
