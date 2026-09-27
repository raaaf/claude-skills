#!/usr/bin/env node
// Renders store stills from a project's `.store-assets/store-assets.json` +
// `templates/scene.html`, using real device bezels + real status-bar
// capture overlays (references/store-specs.md "Devices"). Pre-flight
// validates the config and every source/asset file before any render
// happens (SKILL.md Ablauf, step 4 / Edge Cases).
//
// Usage:
//   node bin/render.mjs --project <path> [--scene <id>] [--format <id>] [--locale <code>]
//                        [--background <hex>] [--out <dir>]
//
// Without --scene/--format/--locale, renders every scene x locale x format
// combination in the config. `play-feature` is not per-scene: it always
// renders once per locale from the config's first scene (the app's hero
// identity), regardless of --scene. `--background`/`--out`: see
// references/config-schema.md "CLI flags".

import { existsSync, mkdirSync, readFileSync, unlinkSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { reviewedHash, parseArgs } from './lib.mjs';

const SKILL_DIR = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const STORE_SPECS_PATH = path.join(SKILL_DIR, 'references', 'store-specs.md');

// Device choice follows the store format, never the scene: ios-6.9 always
// shows an iPhone screen, play-phone always an Android screen, play-feature
// never shows a device at all (scene.html's own `format === 'play-feature'`
// branch drops it).
const DEVICE_BY_FORMAT = { 'ios-6.9': 'iphone', 'play-phone': 'android' };

// iPhone bezel color by scene background (store-specs.md "Devices"), a
// skill-level rule, not a config field. A combo scene's own `ios_color`
// per phone overrides this, except under --background (variant renders
// want one uniform color across the whole strip).
const IPHONE_COLOR_BY_BG = { '#04081f': 'Silver', '#f7f7f7': 'Black', '#e0452f': 'Glacier' };

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function resolveHome(p) {
  return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p;
}

function absFileUrl(absPath) {
  return pathToFileURL(path.resolve(absPath)).href;
}

function projectFileUrl(projectRoot, relPath) {
  return absFileUrl(path.join(projectRoot, relPath));
}

// Extracts the devices spec from references/store-specs.md's "## Devices"
// section (the first ```json fence under that heading) instead of
// hardcoding bezel/status-bar paths in this script (SKILL.md Conventions:
// no brand/machine values in the skill).
function loadDevicesSpec() {
  const text = readFileSync(STORE_SPECS_PATH, 'utf-8');
  const section = text.split(/^## Devices$/m)[1];
  if (!section) fail(`store-specs.md has no "## Devices" section`);
  const match = section.match(/```json\n([\s\S]*?)\n```/);
  if (!match) fail(`store-specs.md's "## Devices" section has no fenced json block`);
  return JSON.parse(match[1]);
}

function devicePaths(devicesSpec, deviceKind, { color, theme }) {
  const spec = devicesSpec[deviceKind];
  const bezelPath = resolveHome(
    color ? spec.bezel_path_pattern.replace('{color}', color) : spec.bezel_path_pattern
  );
  const statusBarPath = resolveHome(spec.status_bar_path_pattern.replace('{theme}', theme));
  const maskPath = spec.mask_path ? resolveHome(spec.mask_path) : null;
  return { bezelPath, statusBarPath, maskPath };
}

function sampleTopColor(pngPath, cropTopPx) {
  const y = cropTopPx + 4;
  const raw = execFileSync('magick', [pngPath, '-format', `%[pixel:p{20,${y}}]`, 'info:'], {
    encoding: 'utf-8',
  });
  return raw.replace(/srgba/g, 'rgba').replace(/srgb/g, 'rgb').trim();
}

function luminance(colorStr) {
  const [r, g, b] = (colorStr.match(/[\d.]+/g) || [0, 0, 0]).map(Number);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
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

function scenePartSources(scene) {
  // Every (locale, theme, path) a scene references, whether a `single`
  // scene's own `source` or a `combo` scene's `front`/`back` sources.
  const sourceMaps = scene.layout === 'combo' ? [scene.combo.front.source, scene.combo.back.source] : [scene.source];
  const entries = [];
  for (const sourceMap of sourceMaps) {
    for (const [locale, byTheme] of Object.entries(sourceMap || {})) {
      for (const [theme, relPath] of Object.entries(byTheme)) entries.push({ locale, theme, relPath });
    }
  }
  return entries;
}

function preflight(projectRoot, config, devicesSpec) {
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
    const parts = scenePartSources(scene);
    for (const locale of config.locales) {
      const forLocale = parts.filter((p) => p.locale === locale);
      if (forLocale.length === 0) {
        missingSources.push(`${scene.id} ${locale} (no source entry)`);
        continue;
      }
      for (const { theme, relPath } of forLocale) {
        const abs = path.join(projectRoot, relPath);
        if (!existsSync(abs)) missingSources.push(`${scene.id} ${locale}/${theme}: ${relPath}`);
      }
    }
  }
  for (const missing of missingSources) problems.push(`MISSING_SOURCE ${missing}`);

  const usedDeviceKinds = new Set(
    Object.entries(DEVICE_BY_FORMAT)
      .filter(([formatId]) => formatId in config.formats)
      .map(([, deviceKind]) => deviceKind)
  );
  for (const deviceKind of usedDeviceKinds) {
    const spec = devicesSpec[deviceKind];
    if (!spec) {
      problems.push(`devices spec missing entry for "${deviceKind}"`);
      continue;
    }
    const colors = spec.colors || [null];
    for (const color of colors) {
      const bezelPath = resolveHome(color ? spec.bezel_path_pattern.replace('{color}', color) : spec.bezel_path_pattern);
      if (!existsSync(bezelPath)) problems.push(`bezel asset not found: ${bezelPath}`);
    }
    for (const theme of ['light', 'dark']) {
      const statusBarPath = resolveHome(spec.status_bar_path_pattern.replace('{theme}', theme));
      if (!existsSync(statusBarPath)) problems.push(`status-bar asset not found: ${statusBarPath}`);
    }
    if (spec.mask_path && !existsSync(resolveHome(spec.mask_path))) {
      problems.push(`mask asset not found: ${resolveHome(spec.mask_path)}`);
    }
  }

  for (const scene of config.scenes) {
    for (const locale of config.locales) {
      const text = scene.text?.[locale];
      if (!text) continue;
      const currentHash = reviewedHash(text.headline, text.subline || '');
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

function buildPhoneSpec({ projectRoot, devicesSpec, deviceKind, part, locale, iosColor }) {
  const byTheme = part.source[locale];
  const theme = byTheme.light ? 'light' : Object.keys(byTheme)[0];
  const screenPath = path.join(projectRoot, byTheme[theme]);
  const topColor = sampleTopColor(screenPath, part.crop_top_px ?? 0);
  const barTheme = luminance(topColor) < 0.5 ? 'light' : 'dark';
  const { bezelPath, statusBarPath, maskPath } = devicePaths(devicesSpec, deviceKind, {
    color: deviceKind === 'iphone' ? iosColor : undefined,
    theme: barTheme,
  });
  return {
    screenSrc: absFileUrl(screenPath),
    cropTopPx: part.crop_top_px ?? 0,
    topColor,
    bezelSrc: absFileUrl(bezelPath),
    statusBarSrc: absFileUrl(statusBarPath),
    maskSrc: maskPath ? absFileUrl(maskPath) : '',
  };
}

function deviceSpecParam(devicesSpec, deviceKind) {
  const spec = devicesSpec[deviceKind];
  return JSON.stringify({
    w: spec.bezel_size.width,
    h: spec.bezel_size.height,
    sx: spec.screen_rect.x,
    sy: spec.screen_rect.y,
    sw: spec.screen_rect.width,
    sh: spec.screen_rect.height,
    r: spec.corner_radius,
    sb: spec.status_bar_band_height,
    widthPct: spec.width_pct,
    screenOverBezel: !!spec.screen_over_bezel,
  });
}

function baseParams(projectRoot, config, format, scene, locale) {
  const text = scene.text[locale];
  if (!text) fail(`scene ${scene.id} has no text for locale ${locale}`);
  const params = {
    format: format.id,
    width: String(format.width),
    height: String(format.height),
    bg: scene.background,
    fg: scene.foreground,
    headlineFont: projectFileUrl(projectRoot, config.brand.headline_font.path),
    headlineFamily: config.brand.headline_font.family,
    sublineFont: projectFileUrl(projectRoot, config.brand.subline_font.path),
    sublineFamily: config.brand.subline_font.family,
    headline: text.headline,
    subline: text.subline || '',
    logoSrc: projectFileUrl(projectRoot, config.brand.logo),
  };
  if (scene.pills?.[locale]) {
    params.pill1 = scene.pills[locale][0] || '';
    params.pill2 = scene.pills[locale][1] || '';
  }
  return params;
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
  // Every bezel/status-bar/screenshot/mask image must be fully decoded
  // before capture; scene.html's readiness flag only covers fonts + the
  // headline shrink-to-fit.
  await page.evaluate(() =>
    Promise.all(
      Array.from(document.images)
        .filter((img) => !img.complete)
        .map((img) => new Promise((resolve) => {
          img.addEventListener('load', resolve, { once: true });
          img.addEventListener('error', resolve, { once: true });
        }))
    )
  );

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

function sceneUrlFor(params) {
  return pathToFileURL(path.join(SKILL_DIR, 'templates', 'scene.html')).href + '?' + new URLSearchParams(params).toString();
}

async function renderOne({ projectRoot, config, devicesSpec, scene, format, locale, backgroundOverride }) {
  const deviceKind = DEVICE_BY_FORMAT[format.id];
  const background = backgroundOverride ?? scene.background;
  const foreground = backgroundOverride ? '#ffffff' : scene.foreground;
  const effectiveScene = { ...scene, background, foreground };

  const params = { ...baseParams(projectRoot, config, format, effectiveScene, locale), layout: scene.layout || 'single', device: deviceKind };
  params.deviceSpec = deviceSpecParam(devicesSpec, deviceKind);

  if (scene.layout === 'combo') {
    const iosColorOverride = backgroundOverride ? IPHONE_COLOR_BY_BG[backgroundOverride] : null;
    const front = buildPhoneSpec({ projectRoot, devicesSpec, deviceKind, part: scene.combo.front, locale, iosColor: iosColorOverride || scene.combo.front.ios_color });
    const back = buildPhoneSpec({ projectRoot, devicesSpec, deviceKind, part: scene.combo.back, locale, iosColor: iosColorOverride || scene.combo.back.ios_color });
    params.front = JSON.stringify(front);
    params.back = JSON.stringify(back);
  } else {
    const iosColor = backgroundOverride ? IPHONE_COLOR_BY_BG[backgroundOverride] : IPHONE_COLOR_BY_BG[scene.background];
    const single = buildPhoneSpec({ projectRoot, devicesSpec, deviceKind, part: scene, locale, iosColor });
    Object.assign(params, {
      screenSrc: single.screenSrc,
      cropTopPx: String(single.cropTopPx),
      topColor: single.topColor,
      bezelSrc: single.bezelSrc,
      statusBarSrc: single.statusBarSrc,
      maskSrc: single.maskSrc,
    });
  }

  return { sceneUrl: sceneUrlFor(params) };
}

async function renderFeatureGraphic({ projectRoot, config, devicesSpec, format, locale }) {
  const heroScene = config.scenes[0];
  const params = baseParams(projectRoot, config, format, heroScene, locale);
  // Fills play-feature's otherwise-empty right half with the hero's own
  // front phone (Pixel-framed, config-schema.md "CLI flags" neighbor
  // section "Devices"); a project whose hero isn't a combo scene simply
  // gets no device here (scene.html's isLandscape branch handles absence).
  if (heroScene.layout === 'combo') {
    const front = buildPhoneSpec({
      projectRoot,
      devicesSpec,
      deviceKind: 'android',
      part: heroScene.combo.front,
      locale,
      iosColor: null,
    });
    params.device = 'android';
    params.deviceSpec = deviceSpecParam(devicesSpec, 'android');
    params.front = JSON.stringify(front);
  }
  return { sceneUrl: sceneUrlFor(params) };
}

async function writeIndex(projectRoot, config, generatedRoot) {
  const rows = [];
  for (const formatId of Object.keys(config.formats)) {
    for (const locale of config.locales) {
      const dir = path.join(generatedRoot, formatId, locale);
      if (!existsSync(dir)) continue;
      const files = readdirSync(dir).filter((f) => f.endsWith('.jpg')).sort();
      rows.push({ formatId, locale, files });
    }
  }
  const html = `<!doctype html>
<html lang="en">
<head><meta charset="UTF-8"><title>store-assets contact sheet</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 24px; background: #111; color: #eee; }
  h2 { margin-top: 32px; }
  .grid { display: flex; flex-wrap: wrap; gap: 12px; }
  .grid img { height: 320px; border-radius: 8px; border: 1px solid #333; }
  figure { margin: 0; text-align: center; }
  figcaption { font-size: 12px; color: #999; margin-top: 4px; }
</style></head>
<body>
<h1>store-assets contact sheet</h1>
${rows
  .map(
    (row) => `<h2>${row.formatId} / ${row.locale}</h2><div class="grid">${row.files
      .map((f) => `<figure><img src="${row.formatId}/${row.locale}/${f}" alt="${f}"><figcaption>${f}</figcaption></figure>`)
      .join('')}</div>`
  )
  .join('\n')}
</body>
</html>
`;
  writeFileSync(path.join(generatedRoot, 'index.html'), html);
  return path.join(generatedRoot, 'index.html');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) fail('--project <path> is required');
  const projectRoot = path.resolve(args.project);
  if (!existsSync(projectRoot)) fail(`project not found: ${projectRoot}`);

  const config = loadConfig(projectRoot);
  const devicesSpec = loadDevicesSpec();
  preflight(projectRoot, config, devicesSpec);

  const scenes = args.scene ? config.scenes.filter((s) => s.id === args.scene) : config.scenes;
  if (args.scene && scenes.length === 0) fail(`unknown scene: ${args.scene}`);
  const formatIds = args.format ? [args.format] : Object.keys(config.formats);
  const locales = args.locale ? [args.locale] : config.locales;
  const backgroundOverride = args.background || null;

  const { chromium } = await resolvePlaywright(projectRoot);

  const written = [];
  for (const formatId of formatIds) {
    const format = { id: formatId, ...config.formats[formatId] };
    const outDirFor = (locale) =>
      args.out ? path.resolve(projectRoot, args.out) : path.join(projectRoot, 'native', 'store-assets', 'generated', formatId, locale);

    if (formatId === 'play-feature') {
      for (const locale of locales) {
        const { sceneUrl } = await renderFeatureGraphic({ projectRoot, config, devicesSpec, format, locale });
        const out = await shootScene(sceneUrl, format, outDirFor(locale), 'feature-graphic', chromium);
        console.log(`WROTE ${out}`);
        written.push(out);
      }
      continue;
    }
    for (const scene of scenes) {
      for (const locale of locales) {
        const { sceneUrl } = await renderOne({ projectRoot, config, devicesSpec, scene, format, locale, backgroundOverride });
        const out = await shootScene(sceneUrl, format, outDirFor(locale), scene.id, chromium);
        console.log(`WROTE ${out}`);
        written.push(out);
      }
    }
  }
  console.log(`OK rendered=${written.length}`);

  if (!args.out && !args.scene && !args.format && !args.locale) {
    const generatedRoot = path.join(projectRoot, 'native', 'store-assets', 'generated');
    const indexPath = await writeIndex(projectRoot, config, generatedRoot);
    console.log(`INDEX ${indexPath}`);
  }
}

main().catch((err) => fail(err.stack || err.message));
