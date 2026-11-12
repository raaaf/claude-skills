#!/usr/bin/env node
// Responsive / touch / slow-network capture for /field-test. One headless Chromium per run (Playwright from the
// private cache shared with screens and store-assets, never installed into the project being checked), one fresh
// context per cell so parallel threads never share a profile.
//
// Usage: web-matrix.mjs --base-url <url> --routes-file <file> --out <dir>
//          [--login-url <url>] [--role <name>] [--throttle] [--widths 320,375,768,1024,1440] [--dark]
//   --routes-file  one path per line (`/`, `/pricing`), blank lines and `#` comments ignored.
//   --login-url    page visited once per context before the routes (e.g. a local dev-login URL); `{role}` in it is
//                  replaced by --role, else `/<role>` is appended when --role is given.
//   --throttle     additionally captures every route at 375 px on Slow 3G (CDP: 400 kbit/s, 2000 ms latency).
//   --dark         additionally captures every cell with prefers-color-scheme dark (and the `dark` class on <html>).
// Touch (hasTouch + isMobile) is on for widths <= 1024.
// Writes <out>/<slug>__<width>__<theme>[__3g].png (full page) and <out>/metrics.json, one record per PNG:
//   overflowPx (document scrollWidth minus viewport), smallTapTargets (visible interactive elements under 44x44 css px,
//   only measured on touch widths, `smallTapTargetSamples` lists up to 10), cls (layout shift sum after load),
//   timeToContentMs (first contentful paint, else load event), loadMs, status (HTTP status of the navigation).
// Exit 0 when every cell ran, 1 when any cell failed (recorded in metrics.json with `error`), 2 usage.

import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const PLAYWRIGHT_PIN = '1.63.0'; // keep equal to screens/bin/ui-shots.mjs and store-assets/bin/render.mjs
const CACHE_ROOT = path.join(os.homedir(), '.cache', 'store-assets');
const DEFAULT_WIDTHS = [320, 375, 768, 1024, 1440];
const SLOW_3G = { latency: 2000, kbps: 400 };
const TOUCH_MAX_WIDTH = 1024;

const VALUE_FLAGS = { '--base-url': 'baseUrl', '--routes-file': 'routesFile', '--out': 'out', '--login-url': 'loginUrl', '--role': 'role', '--widths': 'widths' };

export function parseArgs(argv) {
  const o = { throttle: false, dark: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--throttle') o.throttle = true;
    else if (a === '--dark') o.dark = true;
    else if (a in VALUE_FLAGS) {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) throw new Error(`${a} needs a value`);
      o[VALUE_FLAGS[a]] = v;
    } else throw new Error(`unknown argument ${a}`);
  }
  for (const [flag, key] of [['--base-url', 'baseUrl'], ['--routes-file', 'routesFile'], ['--out', 'out']]) {
    if (!o[key]) throw new Error(`${flag} is required`);
  }
  if (!existsSync(o.routesFile)) throw new Error(`routes file not found: ${o.routesFile}`);
  o.widths = o.widths ? o.widths.split(',').map(Number) : DEFAULT_WIDTHS;
  if (o.widths.some((w) => !Number.isInteger(w) || w < 200)) throw new Error('--widths needs integers >= 200');
  o.baseUrl = o.baseUrl.replace(/\/$/, '');
  return o;
}

export function slugFor(route) {
  const s = route.replace(/^\/+|\/+$/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return s || 'home';
}

export function cellName(route, width, theme, throttled) {
  return `${slugFor(route)}__${width}__${theme}${throttled ? '__3g' : ''}.png`;
}

async function loadPlaywright() {
  const prefix = path.join(CACHE_ROOT, 'npm');
  const pkgDir = path.join(prefix, 'node_modules', 'playwright');
  mkdirSync(prefix, { recursive: true });
  if (!existsSync(pkgDir)) {
    console.error(`INFO: installing playwright@${PLAYWRIGHT_PIN} into ${prefix}`);
    execFileSync('npm', ['install', '--prefix', prefix, '--no-save', '--no-audit', '--no-fund', `playwright@${PLAYWRIGHT_PIN}`], { stdio: 'inherit' });
  }
  const browsersPath = path.join(CACHE_ROOT, 'browsers');
  process.env.PLAYWRIGHT_BROWSERS_PATH = browsersPath;
  if (!existsSync(browsersPath) || !readdirSync(browsersPath).some((d) => d.startsWith('chromium'))) {
    console.error(`INFO: installing chromium into ${browsersPath}`);
    execFileSync('node', [path.join(pkgDir, 'cli.js'), 'install', 'chromium'], { stdio: 'inherit', env: process.env });
  }
  return import(pathToFileURL(path.join(pkgDir, 'index.mjs')).href);
}

const INIT_CLS = () => {
  window.__cls = 0;
  try {
    new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; })
      .observe({ type: 'layout-shift', buffered: true });
  } catch { /* layout-shift unsupported */ }
};

/** Runs inside the page. */
const MEASURE = (measureTaps) => {
  const nav = performance.getEntriesByType('navigation')[0];
  const fcp = performance.getEntriesByName('first-contentful-paint')[0];
  const out = {
    overflowPx: Math.max(0, document.documentElement.scrollWidth - window.innerWidth),
    cls: Math.round((window.__cls || 0) * 1000) / 1000,
    timeToContentMs: Math.round(fcp ? fcp.startTime : (nav ? nav.loadEventEnd : 0)),
    loadMs: Math.round(nav ? nav.loadEventEnd : 0),
  };
  if (measureTaps) {
    const sel = 'a[href], button, input:not([type=hidden]), select, textarea, summary, [role=button], [role=link], [role=tab], [tabindex]:not([tabindex="-1"])';
    const small = [];
    for (const el of document.querySelectorAll(sel)) {
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      if (r.width === 0 || r.height === 0 || cs.visibility === 'hidden' || cs.display === 'none') continue;
      if (r.width < 44 || r.height < 44) {
        small.push(`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''} "${(el.innerText || el.getAttribute('aria-label') || '').trim().slice(0, 30)}" ${Math.round(r.width)}x${Math.round(r.height)}`);
      }
    }
    out.smallTapTargets = small.length;
    out.smallTapTargetSamples = small.slice(0, 10);
  }
  return out;
};

function loginTarget(o) {
  if (!o.loginUrl) return null;
  if (o.loginUrl.includes('{role}')) return o.loginUrl.replace('{role}', encodeURIComponent(o.role || ''));
  return o.role ? `${o.loginUrl.replace(/\/$/, '')}/${encodeURIComponent(o.role)}` : o.loginUrl;
}

async function captureCell(browser, o, route, width, theme, throttled) {
  const touch = width <= TOUCH_MAX_WIDTH;
  const height = width <= 480 ? 812 : width <= TOUCH_MAX_WIDTH ? 1024 : 900;
  const context = await browser.newContext({
    viewport: { width, height }, hasTouch: touch, isMobile: touch && width < 768,
    colorScheme: theme === 'dark' ? 'dark' : 'light', reducedMotion: 'no-preference',
  });
  const name = cellName(route, width, theme, throttled);
  const rec = { file: name, route, width, theme, throttled, touch };
  try {
    await context.addInitScript(INIT_CLS);
    const page = await context.newPage();
    const login = loginTarget(o);
    if (login) await page.goto(login, { waitUntil: 'load', timeout: 60000 });
    if (throttled) {
      const cdp = await context.newCDPSession(page);
      await cdp.send('Network.enable');
      const bps = (SLOW_3G.kbps * 1000) / 8;
      await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: SLOW_3G.latency, downloadThroughput: bps, uploadThroughput: bps });
    }
    const resp = await page.goto(`${o.baseUrl}${route}`, { waitUntil: 'load', timeout: throttled ? 180000 : 60000 });
    rec.status = resp ? resp.status() : null;
    if (!throttled) await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    if (theme === 'dark') await page.evaluate(() => document.documentElement.classList.add('dark'));
    await page.waitForTimeout(1000);
    Object.assign(rec, await page.evaluate(MEASURE, touch));
    await page.screenshot({ path: path.join(o.out, name), fullPage: true, animations: 'disabled' });
  } catch (e) {
    rec.error = String(e.message || e).split('\n')[0];
  } finally {
    await context.close();
  }
  return rec;
}

async function main() {
  let o;
  try { o = parseArgs(process.argv.slice(2)); } catch (e) { console.error(`web-matrix: ${e.message}`); process.exit(2); }
  mkdirSync(o.out, { recursive: true });
  const routes = readFileSync(o.routesFile, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const { chromium } = await loadPlaywright();
  const browser = await chromium.launch();
  const records = [];
  try {
    for (const route of routes) {
      for (const width of o.widths) {
        for (const theme of o.dark ? ['light', 'dark'] : ['light']) {
          records.push(await captureCell(browser, o, route, width, theme, false));
        }
      }
      if (o.throttle) records.push(await captureCell(browser, o, route, 375, 'light', true));
    }
  } finally {
    await browser.close();
  }
  writeFileSync(path.join(o.out, 'metrics.json'), JSON.stringify(records, null, 2));
  const failed = records.filter((r) => r.error);
  console.log(`web-matrix: ${records.length - failed.length}/${records.length} cells ok -> ${o.out}`);
  for (const r of failed) console.error(`FAILED ${r.file}: ${r.error}`);
  process.exit(failed.length ? 1 : 0);
}

// import.meta.url is the realpath; argv[1] may be a symlink (skills are symlinked into ~/.claude/skills).
const isMain = process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
if (isMain) await main();
