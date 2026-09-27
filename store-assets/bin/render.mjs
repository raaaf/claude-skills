#!/usr/bin/env node
// Renders store stills from a project's `.store-assets/store-assets.json` +
// `templates/scene.html`. Pre-flight validates the config and every source
// file before any render happens (SKILL.md Ablauf, step 4 / Edge Cases).
//
// Usage:
//   node bin/render.mjs --project <path> [--scene <id>] [--format <id>] [--locale <code>]
//
// Without --scene/--format/--locale, renders every scene x locale x format
// combination in the config. With all three given, renders exactly one file
// (used by the Step 4 verify sample and for quick iteration). `play-feature`
// is not per-scene: it always renders once per locale from the config's
// first scene (the app's hero identity), regardless of --scene.

import { existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { reviewedHash, parseArgs } from './lib.mjs';

const SKILL_DIR = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

// Device choice follows the store format, never the scene (REVISE round 1):
// ios-6.9 always shows an iPhone screen, play-phone always an Android
// screen, play-feature never shows a device at all (scene.html's own
// `format === 'play-feature'` branch drops it).
const DEVICE_BY_FORMAT = { 'ios-6.9': 'iphone', 'play-phone': 'android' };

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function loadConfig(projectRoot) {
  const configPath = path.join(projectRoot, '.store-assets', 'store-assets.json');
  if (!existsSync(configPath)) fail(`config not found: ${configPath}`);
  let config;
  try {
    config = JSON.parse(readFileSync(configPath, 'utf-8'));
  } catch (err) {
    fail(`config is not valid JSON: ${err.message}`);
  }
  for (const key of ['brand', 'locales', 'formats', 'scenes', 'runtime']) {
    if (!(key in config)) fail(`config missing required top-level field: ${key}`);
  }
  return config;
}

function preflight(projectRoot, config) {
  const problems = [];
  const missingSources = [];

  for (const font of [config.brand.headline_font, config.brand.subline_font]) {
    const fontPath = path.join(projectRoot, font.path);
    if (!existsSync(fontPath)) problems.push(`font not found: ${font.path}`);
  }
  if (config.brand.logo) {
    const logoPath = path.join(projectRoot, config.brand.logo);
    if (!existsSync(logoPath)) problems.push(`logo not found: ${config.brand.logo}`);
  }

  for (const scene of config.scenes) {
    for (const locale of config.locales) {
      const localeSources = scene.source?.[locale];
      if (!localeSources) {
        missingSources.push(`${scene.id} ${locale} (no source entry)`);
        continue;
      }
      for (const [theme, relPath] of Object.entries(localeSources)) {
        const abs = path.join(projectRoot, relPath);
        if (!existsSync(abs)) missingSources.push(`${scene.id} ${locale}/${theme}: ${relPath}`);
      }
    }
  }

  for (const missing of missingSources) problems.push(`MISSING_SOURCE ${missing}`);

  for (const scene of config.scenes) {
    for (const locale of config.locales) {
      const text = scene.text?.[locale];
      if (!text) continue;
      const currentHash = reviewedHash(text.headline, text.subline);
      const effectivelyReviewed = text.reviewed === true && text.reviewed_hash === currentHash;
      if (!effectivelyReviewed) {
        console.error(`INFO: ${scene.id} ${locale} not reviewed (reviewed=${text.reviewed}, hash ${text.reviewed_hash === currentHash ? 'matches' : 'mismatch'})`);
      }
    }
  }

  if (problems.length) {
    for (const p of problems) console.error(`FAIL: ${p}`);
    process.exit(1);
  }
}

function resolvePlaywright(projectRoot) {
  const projectPkg = path.join(projectRoot, 'node_modules', 'playwright');
  if (existsSync(projectPkg)) return import(pathToFileURL(path.join(projectPkg, 'index.mjs')).href);
  const testPkg = path.join(projectRoot, 'node_modules', '@playwright/test');
  if (existsSync(testPkg)) return import(pathToFileURL(path.join(testPkg, 'index.mjs')).href);
  fail(
    'no project-local playwright/@playwright/test found; fallback is `npx -y playwright@<pinned>` ' +
      'plus `npx playwright install chromium` with PLAYWRIGHT_BROWSERS_PATH=~/.cache/store-assets/browsers ' +
      '(references/store-specs.md "Pinned tool versions"), not implemented in this script yet.'
  );
}

function fileUrl(projectRoot, relPath) {
  return pathToFileURL(path.join(projectRoot, relPath)).href;
}

function baseParams(projectRoot, config, formatId, format, scene, locale) {
  const text = scene.text[locale];
  if (!text) fail(`scene ${scene.id} has no text for locale ${locale}`);
  return {
    format: formatId,
    width: String(format.width),
    height: String(format.height),
    bg: scene.background,
    fg: scene.foreground,
    headlineFont: fileUrl(projectRoot, config.brand.headline_font.path),
    headlineFamily: config.brand.headline_font.family,
    sublineFont: fileUrl(projectRoot, config.brand.subline_font.path),
    sublineFamily: config.brand.subline_font.family,
    headline: text.headline,
    subline: text.subline ?? '',
    logoSrc: fileUrl(projectRoot, config.brand.logo),
  };
}

async function shootScene(sceneUrl, format, outDir, fileId, chromium) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: format.width, height: format.height } });
  await page.goto(sceneUrl);
  await page.waitForFunction(() => document.body.dataset.ready !== undefined, { timeout: 15000 });
  const ready = await page.evaluate(() => document.body.dataset.ready);
  if (ready !== 'true') {
    await browser.close();
    fail(`font failed to load for ${fileId}: document.fonts.check returned false`);
  }

  mkdirSync(outDir, { recursive: true });
  const pngPath = path.join(outDir, `${fileId}.png`);
  const jpgPath = path.join(outDir, `${fileId}.jpg`);
  await page.screenshot({ path: pngPath });
  await browser.close();

  execFileSync('sips', [
    '-s', 'format', 'jpeg',
    '-m', '/System/Library/ColorSync/Profiles/sRGB Profile.icc',
    pngPath,
    '--out', jpgPath,
  ], { stdio: 'inherit' });
  unlinkSync(pngPath);

  return jpgPath;
}

async function renderOne({ projectRoot, config, scene, formatId, locale, chromium }) {
  const format = config.formats[formatId];
  if (!format) fail(`unknown format: ${formatId}`);

  const localeSources = scene.source[locale];
  const theme = localeSources.light ? 'light' : Object.keys(localeSources)[0];

  const params = new URLSearchParams({
    ...baseParams(projectRoot, config, formatId, format, scene, locale),
    device: DEVICE_BY_FORMAT[formatId],
    screenSrc: fileUrl(projectRoot, localeSources[theme]),
    cropTopPx: String(scene.crop_top_px ?? 0),
  });

  const sceneUrl = pathToFileURL(path.join(SKILL_DIR, 'templates', 'scene.html')).href + '?' + params.toString();
  const outDir = path.join(projectRoot, 'native', 'store-assets', 'generated', formatId, locale);
  return shootScene(sceneUrl, format, outDir, scene.id, chromium);
}

async function renderFeatureGraphic({ projectRoot, config, locale, chromium }) {
  const formatId = 'play-feature';
  const format = config.formats[formatId];
  if (!format) fail(`unknown format: ${formatId}`);
  const heroScene = config.scenes[0];

  const params = new URLSearchParams(baseParams(projectRoot, config, formatId, format, heroScene, locale));
  const sceneUrl = pathToFileURL(path.join(SKILL_DIR, 'templates', 'scene.html')).href + '?' + params.toString();
  const outDir = path.join(projectRoot, 'native', 'store-assets', 'generated', formatId, locale);
  return shootScene(sceneUrl, format, outDir, 'feature-graphic', chromium);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) fail('--project <path> is required');
  const projectRoot = path.resolve(args.project);
  if (!existsSync(projectRoot)) fail(`project not found: ${projectRoot}`);

  const config = loadConfig(projectRoot);
  preflight(projectRoot, config);

  const scenes = args.scene ? config.scenes.filter((s) => s.id === args.scene) : config.scenes;
  if (args.scene && scenes.length === 0) fail(`unknown scene: ${args.scene}`);
  const formats = args.format ? [args.format] : Object.keys(config.formats);
  const locales = args.locale ? [args.locale] : config.locales;

  const { chromium } = await resolvePlaywright(projectRoot);

  const written = [];
  for (const formatId of formats) {
    if (formatId === 'play-feature') {
      for (const locale of locales) {
        const out = await renderFeatureGraphic({ projectRoot, config, locale, chromium });
        console.log(`WROTE ${out}`);
        written.push(out);
      }
      continue;
    }
    for (const scene of scenes) {
      for (const locale of locales) {
        const out = await renderOne({ projectRoot, config, scene, formatId, locale, chromium });
        console.log(`WROTE ${out}`);
        written.push(out);
      }
    }
  }
  console.log(`OK rendered=${written.length}`);
}

main().catch((err) => fail(err.stack || err.message));
