#!/usr/bin/env node
// Validates rendered store stills against `references/store-specs.md` and the
// project's own config (SKILL.md Ablauf, step 5).
//
// Usage: node bin/validate.mjs --project <path>
//
// Exit 0 only when every generated file matches its format's exact
// dimensions, has no alpha channel, is under 8 MB, the per-format image
// count is within limits, exactly one play-feature image exists, and every
// rendered scene's text is `reviewed: true` with a matching hash.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { reviewedHash } from './lib.mjs';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      out[argv[i].slice(2)] = argv[i + 1];
      i++;
    }
  }
  return out;
}

const LIMITS = {
  'ios-6.9': { maxCount: 10 },
  'play-phone': { maxCount: 8 },
  'play-feature': { maxCount: 1 },
};

function sipsInfo(filePath) {
  const out = execFileSync('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', '-g', 'space', filePath], {
    encoding: 'utf-8',
  });
  const get = (key) => {
    const m = out.match(new RegExp(`${key}:\\s*(\\S+)`));
    return m ? m[1] : null;
  };
  return {
    width: Number(get('pixelWidth')),
    height: Number(get('pixelHeight')),
    hasAlpha: get('hasAlpha') === 'yes',
    space: get('space'),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) {
    console.error('FAIL: --project <path> is required');
    process.exit(1);
  }
  const projectRoot = path.resolve(args.project);
  const configPath = path.join(projectRoot, '.store-assets', 'store-assets.json');
  if (!existsSync(configPath)) {
    console.error(`FAIL: config not found: ${configPath}`);
    process.exit(1);
  }
  const config = JSON.parse(readFileSync(configPath, 'utf-8'));
  const generatedRoot = path.join(projectRoot, 'native', 'store-assets', 'generated');

  const problems = [];

  for (const [formatId, format] of Object.entries(config.formats)) {
    for (const locale of config.locales) {
      const dir = path.join(generatedRoot, formatId, locale);
      if (!existsSync(dir)) {
        problems.push(`missing output dir: ${formatId}/${locale}`);
        continue;
      }
      const files = readdirSync(dir).filter((f) => f.endsWith('.jpg'));
      const limit = LIMITS[formatId];
      if (limit && files.length > limit.maxCount) {
        problems.push(`${formatId}/${locale}: ${files.length} images exceeds max ${limit.maxCount}`);
      }
      if (formatId === 'play-feature' && files.length !== 1) {
        problems.push(`${formatId}/${locale}: expected exactly 1 feature graphic, found ${files.length}`);
      }
      for (const file of files) {
        const filePath = path.join(dir, file);
        const info = sipsInfo(filePath);
        if (info.width !== format.width || info.height !== format.height) {
          problems.push(`${formatId}/${locale}/${file}: ${info.width}x${info.height}, expected ${format.width}x${format.height}`);
        }
        if (info.hasAlpha) {
          problems.push(`${formatId}/${locale}/${file}: has an alpha channel`);
        }
        const sizeBytes = statSync(filePath).size;
        if (sizeBytes >= 8 * 1024 * 1024) {
          problems.push(`${formatId}/${locale}/${file}: ${(sizeBytes / 1024 / 1024).toFixed(1)} MB exceeds 8 MB`);
        }
      }
    }
  }

  for (const scene of config.scenes) {
    for (const locale of config.locales) {
      const text = scene.text?.[locale];
      if (!text) continue;
      const currentHash = reviewedHash(text.headline, text.subline);
      if (text.reviewed !== true || text.reviewed_hash !== currentHash) {
        problems.push(`${scene.id}/${locale}: not reviewed (reviewed=${text.reviewed}, hash ${text.reviewed_hash === currentHash ? 'matches' : 'mismatch'})`);
      }
    }
  }

  if (problems.length) {
    for (const p of problems) console.error(`FAIL: ${p}`);
    process.exit(1);
  }
  console.log('OK');
}

main();
