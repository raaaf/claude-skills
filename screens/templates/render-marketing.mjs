#!/usr/bin/env node
//
// render-marketing.mjs: instantiated verbatim into `<project>/.screens/web/render-marketing.mjs`
// by the Phase 2 scaffold, alongside `.screens/web/marketing.html` (also copied verbatim from
// `screens/templates/marketing.html`). This is the ONLY file in /screens that imports Playwright:
// the skill repo itself stays dependency-free (repo CLAUDE.md "Stack": no npm dependencies here),
// so rendering runs as a child process of `screens.mjs marketing` (`defaultMarketingRenderer`),
// using the PROJECT's own `@playwright/test` devDependency instead of one this repo would need to
// ship.
//
// Contract: reads a JSON array of jobs from stdin, each
// `{ id, locale, format, headline, background, deviceClass, sourcePng, targetPath }`
// (`sourcePng`/`targetPath` are absolute filesystem paths). Renders `.screens/web/marketing.html`
// with those values substituted, screenshots it with Playwright at exactly `format`'s pixel size,
// and writes each PNG straight to `targetPath` (the review-gate routing into `_marketing/_draft/`
// vs `_marketing/` was already decided by the caller). Prints one JSON array of
// `{ id, locale, format, ok, reason? }` to stdout and exits 0 even when an individual job failed
// (the caller reports per-job failures instead of losing the whole batch).

import { chromium } from '@playwright/test';
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function readStdin() {
  return readFileSync(0, 'utf8');
}

async function main() {
  const jobs = JSON.parse(readStdin());
  const templatePath = join(process.cwd(), '.screens/web/marketing.html');
  const template = readFileSync(templatePath, 'utf8');
  const browser = await chromium.launch();
  const results = [];

  for (const job of jobs) {
    try {
      const [width, height] = job.format.split('x').map(Number);
      const html = template
        .replaceAll('{{WIDTH}}', String(width))
        .replaceAll('{{HEIGHT}}', String(height))
        .replaceAll('{{BACKGROUND}}', job.background)
        .replaceAll('{{HEADLINE}}', escapeHtml(job.headline))
        .replaceAll('{{DEVICE_CLASS}}', job.deviceClass)
        .replaceAll('{{SCREENSHOT_SRC}}', pathToFileURL(job.sourcePng).href);

      // Written to a temp file and navigated to via `file://` rather than
      // `page.setContent` (which leaves the document at `about:blank`):
      // Chromium refuses to load a local `<img src="file://...">` from a
      // non-file:// document origin ("Not allowed to load local resource"),
      // so the catalog screenshot silently failed to load under
      // `setContent`. A real `file://` document origin has no such
      // restriction on sibling local resources.
      const tmpHtmlPath = join(tmpdir(), `screens-marketing-${randomUUID()}.html`);
      writeFileSync(tmpHtmlPath, html);
      const page = await browser.newPage({ viewport: { width, height } });
      try {
        await page.goto(pathToFileURL(tmpHtmlPath).href, { waitUntil: 'networkidle' });
        mkdirSync(dirname(job.targetPath), { recursive: true });
        await page.screenshot({ path: job.targetPath });
      } finally {
        await page.close();
        rmSync(tmpHtmlPath, { force: true });
      }
      results.push({ id: job.id, locale: job.locale, format: job.format, ok: true });
    } catch (err) {
      results.push({ id: job.id, locale: job.locale, format: job.format, ok: false, reason: String(err && err.message || err) });
    }
  }

  await browser.close();
  process.stdout.write(JSON.stringify(results));
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack || err) + '\n');
  process.exit(1);
});
