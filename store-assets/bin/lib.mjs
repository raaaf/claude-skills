// Shared helpers for render.mjs and validate.mjs.
import { createHash } from 'node:crypto';
import path from 'node:path';

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

// CSS `format()` hint for an @font-face src, derived from the font file's
// extension (scene.html must not hardcode one).
const FONT_FORMATS = { woff2: 'woff2', woff: 'woff', ttf: 'truetype', otf: 'opentype' };
export function fontFormat(fontPath) {
  const ext = fontPath.split('.').pop().toLowerCase();
  const format = FONT_FORMATS[ext];
  if (!format) throw new Error(`unsupported font extension ".${ext}" (use woff2, woff, ttf or otf): ${fontPath}`);
  return format;
}

// iPhone bezel color: explicit color (scene/part `ios_color` or a variant
// override) wins, then the background lookup, then the first color listed in
// store-specs.md "Devices" (never undefined).
export function pickIphoneColor({ explicit, background, byBackground, validColors }) {
  return explicit || byBackground[String(background).toLowerCase()] || validColors[0];
}

// Project-relative output root for rendered stills; `output_dir` in the
// config overrides the default.
export const DEFAULT_OUTPUT_DIR = 'native/store-assets/generated';
export function outputRoot(projectRoot, config) {
  return path.join(projectRoot, config.output_dir || DEFAULT_OUTPUT_DIR);
}
