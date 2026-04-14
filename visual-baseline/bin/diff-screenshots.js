#!/usr/bin/env node
/**
 * diff-screenshots.js — Compare baseline vs current screenshots using pixelmatch.
 *
 * Usage: node diff-screenshots.js <screenshots-dir>
 *
 * Expects:
 *   <screenshots-dir>/baseline/{desktop,mobile}/*.png
 *   <screenshots-dir>/current/{desktop,mobile}/*.png
 *
 * Outputs:
 *   <screenshots-dir>/diffs/{desktop,mobile}/diff_*.png  (visual diff images)
 *   <screenshots-dir>/report.json                        (diff results)
 *   stdout: JSON summary
 */

const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const pixelmatchModule = require('pixelmatch');
const pixelmatch = pixelmatchModule.default || pixelmatchModule;

const screenshotsDir = process.argv[2];
if (!screenshotsDir) {
  console.error('Usage: node diff-screenshots.js <screenshots-dir>');
  process.exit(1);
}

const baselineDir = path.join(screenshotsDir, 'baseline');
const currentDir = path.join(screenshotsDir, 'current');
const diffsDir = path.join(screenshotsDir, 'diffs');

if (!fs.existsSync(baselineDir) || !fs.existsSync(currentDir)) {
  console.error('Missing baseline/ or current/ directory');
  process.exit(1);
}

// Ensure diffs directories exist
for (const sub of ['desktop', 'mobile']) {
  fs.mkdirSync(path.join(diffsDir, sub), { recursive: true });
}

const results = [];

for (const viewport of ['desktop', 'mobile']) {
  const baseViewportDir = path.join(baselineDir, viewport);
  const currViewportDir = path.join(currentDir, viewport);

  if (!fs.existsSync(baseViewportDir) || !fs.existsSync(currViewportDir)) continue;

  const currentFiles = fs.readdirSync(currViewportDir).filter(f => f.endsWith('.png'));

  for (const file of currentFiles) {
    const baseFile = path.join(baseViewportDir, file);
    const currFile = path.join(currViewportDir, file);
    const diffFile = path.join(diffsDir, viewport, `diff_${file}`);

    if (!fs.existsSync(baseFile)) {
      results.push({
        file: `${viewport}/${file}`,
        status: 'new',
        diffPixels: 0,
        diffPercent: 0,
        diffImage: null
      });
      continue;
    }

    const baseline = PNG.sync.read(fs.readFileSync(baseFile));
    const current = PNG.sync.read(fs.readFileSync(currFile));

    // Handle size differences — use the larger dimensions
    const width = Math.max(baseline.width, current.width);
    const height = Math.max(baseline.height, current.height);

    // Resize images to same dimensions if needed
    const resized1 = resizeToFit(baseline, width, height);
    const resized2 = resizeToFit(current, width, height);

    const diff = new PNG({ width, height });

    const diffPixels = pixelmatch(
      resized1.data, resized2.data, diff.data,
      width, height,
      {
        threshold: 0.15,       // sensitivity: lower = more sensitive
        alpha: 0.3,            // opacity of unchanged pixels in diff
        diffColor: [255, 0, 100],     // highlight color for differences
        diffColorAlt: [0, 180, 255],  // alternate diff color
        aaColor: [255, 255, 0]        // anti-aliasing diff color
      }
    );

    const totalPixels = width * height;
    const diffPercent = parseFloat(((diffPixels / totalPixels) * 100).toFixed(2));

    // Only write diff image if there are actual differences
    if (diffPixels > 0) {
      fs.writeFileSync(diffFile, PNG.sync.write(diff));
    }

    results.push({
      file: `${viewport}/${file}`,
      status: diffPixels === 0 ? 'identical' : 'changed',
      diffPixels,
      diffPercent,
      totalPixels,
      baselineSize: { width: baseline.width, height: baseline.height },
      currentSize: { width: current.width, height: current.height },
      diffImage: diffPixels > 0 ? `diffs/${viewport}/diff_${file}` : null
    });
  }
}

// Summary
const changed = results.filter(r => r.status === 'changed');
const identical = results.filter(r => r.status === 'identical');
const newScreenshots = results.filter(r => r.status === 'new');

const report = {
  generated: new Date().toISOString(),
  summary: {
    total: results.length,
    changed: changed.length,
    identical: identical.length,
    new: newScreenshots.length,
    maxDiffPercent: changed.length > 0
      ? Math.max(...changed.map(r => r.diffPercent))
      : 0,
    avgDiffPercent: changed.length > 0
      ? parseFloat((changed.reduce((sum, r) => sum + r.diffPercent, 0) / changed.length).toFixed(2))
      : 0
  },
  results
};

// Write report
fs.writeFileSync(path.join(screenshotsDir, 'report.json'), JSON.stringify(report, null, 2));

// Print summary to stdout
console.log(JSON.stringify(report, null, 2));

/**
 * Resize a PNG to fit within target dimensions, padding with transparent pixels.
 */
function resizeToFit(png, targetWidth, targetHeight) {
  if (png.width === targetWidth && png.height === targetHeight) return png;

  const resized = new PNG({ width: targetWidth, height: targetHeight, fill: true });

  // Fill with transparent white
  for (let i = 0; i < resized.data.length; i += 4) {
    resized.data[i] = 255;
    resized.data[i + 1] = 255;
    resized.data[i + 2] = 255;
    resized.data[i + 3] = 255;
  }

  // Copy original pixels
  for (let y = 0; y < png.height && y < targetHeight; y++) {
    for (let x = 0; x < png.width && x < targetWidth; x++) {
      const srcIdx = (y * png.width + x) * 4;
      const dstIdx = (y * targetWidth + x) * 4;
      resized.data[dstIdx] = png.data[srcIdx];
      resized.data[dstIdx + 1] = png.data[srcIdx + 1];
      resized.data[dstIdx + 2] = png.data[srcIdx + 2];
      resized.data[dstIdx + 3] = png.data[srcIdx + 3];
    }
  }

  return resized;
}
