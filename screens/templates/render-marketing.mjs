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
// `{ id, locale, format, headline, background, layout, domain, desktopSrc, mobileSrc,
//    fontFamily, regularFontPath, boldFontPath, logoPath, targetPath }`
// (`desktopSrc`/`mobileSrc`/`regularFontPath`/`boldFontPath`/`logoPath`/`targetPath` are absolute
// filesystem paths, any of them may be null). Renders `.screens/web/marketing.html` with those
// values substituted, screenshots it with Playwright at exactly `format`'s pixel size (device
// scale factor 1 -- `desktopSrc`/`mobileSrc` already carry the 2x detail, see
// `screens/references/config-schema.md` "marketing.source_scale"), and writes each PNG straight to
// `targetPath` (the review-gate routing into `_marketing/_draft/` vs `_marketing/` was already
// decided by the caller). Prints one JSON array of `{ id, locale, format, ok, reason? }` to stdout
// and exits 0 even when an individual job failed (the caller reports per-job failures instead of
// losing the whole batch).

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

// @font-face block for the two local weights `resolveMarketingFont`
// (screens.mjs) found, referenced by `file://` URL (Typography spec: "no
// CDN"). Either path may be null (no local font file found), in which case
// the placeholder resolves to an empty string and the template's
// `-apple-system` fallback chain applies.
function buildFontFaceCss(job) {
  const rules = [];
  if (job.regularFontPath) {
    rules.push(`@font-face { font-family: '${job.fontFamily}'; font-weight: 400; font-style: normal; src: url('${pathToFileURL(job.regularFontPath).href}') format('woff2'); }`);
  }
  if (job.boldFontPath) {
    rules.push(`@font-face { font-family: '${job.fontFamily}'; font-weight: 600; font-style: normal; src: url('${pathToFileURL(job.boldFontPath).href}') format('woff2'); }`);
  }
  return rules.join('\n');
}

function buildLogoBlock(job) {
  if (!job.logoPath) return '';
  // Contrast (`backgroundIsDark` in screens.mjs): a dark-on-dark logo asset
  // (e.g. a near-black wordmark against this render's own near-black
  // gradient) gets inverted to white instead of rendering unreadable.
  const style = job.logoInvert ? ' style="filter: brightness(0) invert(1)"' : '';
  return `<div class="logo"><img src="${pathToFileURL(job.logoPath).href}"${style}></div>`;
}

// iPhone frame block ("browser-phone" layout only, `resolveMarketingLayout`
// in screens.mjs already decided which entries get one); empty string
// collapses the template to the plain "browser" layout.
function buildPhoneBlock(job) {
  if (job.layout !== 'browser-phone' || !job.mobileSrc) return '';
  return `<div class="iphone-frame"><div class="iphone-side-button"></div><div class="iphone-screen"><div class="dynamic-island"></div><img src="${pathToFileURL(job.mobileSrc).href}"></div></div>`;
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
        .replaceAll('{{DOMAIN}}', escapeHtml(job.domain))
        .replaceAll('{{TEXT_COLOR}}', job.textColor)
        .replaceAll('{{FONT_FAMILY}}', job.fontFamily)
        .replaceAll('{{FONT_FACE_CSS}}', buildFontFaceCss(job))
        .replaceAll('{{LOGO_BLOCK}}', buildLogoBlock(job))
        .replaceAll('{{PHONE_BLOCK}}', buildPhoneBlock(job))
        .replaceAll('{{DESKTOP_SRC}}', pathToFileURL(job.desktopSrc).href);

      // Written to a temp file and navigated to via `file://` rather than
      // `page.setContent` (which leaves the document at `about:blank`):
      // Chromium refuses to load a local `<img src="file://...">` from a
      // non-file:// document origin ("Not allowed to load local resource"),
      // so the catalog screenshot silently failed to load under
      // `setContent`. A real `file://` document origin has no such
      // restriction on sibling local resources.
      const tmpHtmlPath = join(tmpdir(), `screens-marketing-${randomUUID()}.html`);
      writeFileSync(tmpHtmlPath, html);
      // deviceScaleFactor 1 on purpose (Render spec): the canvas itself is
      // exactly `format`'s pixel size, and `desktopSrc`/`mobileSrc` already
      // carry the 2x detail the browser/phone mockups downsample from.
      const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
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
