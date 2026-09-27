// Shared helpers for render.mjs and validate.mjs.
import { createHash } from 'node:crypto';

// SHA-256 of headline+subline, the `reviewed_hash` contract in
// references/config-schema.md ("Headline nach Freigabe geändert").
export function reviewedHash(headline, subline) {
  return createHash('sha256').update(headline + subline).digest('hex');
}
