#!/usr/bin/env node
// Self-check shots for a web UI task: one browser launch, exactly three screenshots
// (375px light, 375px dark, 1280px light) of one URL, written to an output directory.
//
// Usage (run it through the test-lock admission so parallel runs queue):
//   bash <skills>/audit/bin/test-lock.sh --cmd "node ui-shots.mjs --url <url> [--out <dir>] [auth options]"
//
// Options:
//   --url <url>                     page to shoot (http, https or file)
//   --out <dir>                     output directory (default: a new temp directory)
//   --login-url <url>               GET this URL first; its cookies carry into the shots (dev login route)
//   --form-login <url> <user-field> <pass-field>
//                                   fill and submit a login form; needs --creds-file
//   --creds-file <path>             two lines: user, then password (never pass credentials as arguments)
//
// Prints the image paths, the final URL and the page title. If the final URL looks like a login page
// the result is "SELF-CHECK: unreachable" and the exit code is 2. Every shot's final URL is checked, plus a
// visible password input as a second login signal; a login that does not succeed also exits 2. One retry per shot, no re-shoot loop.
//
// Playwright comes from the private cache shared with store-assets (~/.cache/store-assets): the pinned
// version is installed there once if missing. Nothing is ever installed into the project being checked.

import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const PLAYWRIGHT_PIN = '1.63.0'; // keep equal to store-assets/bin/render.mjs
const CACHE_ROOT = path.join(os.homedir(), '.cache', 'store-assets');
const SHOTS = [
  { name: '375-light', width: 375, height: 812, scheme: 'light' },
  { name: '375-dark', width: 375, height: 812, scheme: 'dark' },
  { name: '1280-light', width: 1280, height: 800, scheme: 'light' },
];
const LOGIN_PATH = /\/(login|log-in|signin|sign-in|sign_in|anmelden|session\/new|auth)(\/|$)/i;

const VALUE_FLAGS = { '--url': 'url', '--out': 'out', '--login-url': 'loginUrl', '--creds-file': 'credsFile' };

/** Parses and validates all arguments. Throws on anything unknown or incomplete; credentials are never accepted from argv. */
export function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg in VALUE_FLAGS) {
      const value = argv[++i];
      if (value === undefined || value.startsWith('--')) throw new Error(`${arg} needs a value`);
      opts[VALUE_FLAGS[arg]] = value;
    } else if (arg === '--form-login') {
      const [url, userField, passField] = argv.slice(i + 1, i + 4);
      if (!url || !userField || !passField || [url, userField, passField].some((v) => v.startsWith('--'))) {
        throw new Error('--form-login needs <url> <user-field> <pass-field>');
      }
      opts.formLogin = { url, userField, passField };
      i += 3;
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  if (!opts.url) throw new Error('--url is required');
  if (opts.formLogin && opts.loginUrl) throw new Error('use either --login-url or --form-login');
  if (opts.formLogin && !opts.credsFile) throw new Error('--form-login needs --creds-file');
  if (opts.credsFile && !opts.formLogin) throw new Error('--creds-file only belongs to --form-login');
  if (opts.credsFile && !existsSync(opts.credsFile)) throw new Error(`creds file not found: ${opts.credsFile}`);
  return opts;
}

/** A URL path that names a login page. */
export function isLoginUrl(url) {
  try {
    return LOGIN_PATH.test(new URL(url).pathname + '/');
  } catch {
    return false;
  }
}

/** Login page by URL, or by a visible password input as a second signal. */
async function isLoginPage(page) {
  if (isLoginUrl(page.url())) return true;
  return (await page.locator('input[type="password"]:visible').count()) > 0;
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

async function login(browser, opts) {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    if (opts.loginUrl) {
      await page.goto(opts.loginUrl, { waitUntil: 'networkidle' });
    } else {
      const [user, pass] = readFileSync(opts.credsFile, 'utf8').split('\n');
      const { url, userField, passField } = opts.formLogin;
      await page.goto(url, { waitUntil: 'networkidle' });
      await page.fill(`[name="${userField}"]`, user);
      await page.fill(`[name="${passField}"]`, pass);
      await Promise.all([page.waitForLoadState('networkidle'), page.press(`[name="${passField}"]`, 'Enter')]);
    }
    if (await isLoginPage(page)) return null;
    return await context.storageState();
  } finally {
    await context.close();
  }
}

async function shoot(browser, shot, opts, state, outDir) {
  const context = await browser.newContext({
    viewport: { width: shot.width, height: shot.height },
    colorScheme: shot.scheme,
    ...(state ? { storageState: state } : {}),
  });
  try {
    const page = await context.newPage();
    await page.goto(opts.url, { waitUntil: 'networkidle' });
    const file = path.join(outDir, `${shot.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    return { file, finalUrl: page.url(), title: await page.title(), loginPage: await isLoginPage(page) };
  } finally {
    await context.close();
  }
}

/** Returns the exit code: 0 ok, 1 error, 2 unreachable (login not possible or a shot landed on a login page). */
async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    return 1;
  }
  const outDir = opts.out ? path.resolve(opts.out) : mkdtempSync(path.join(os.tmpdir(), 'ui-shots-'));
  mkdirSync(outDir, { recursive: true });

  const { chromium } = await loadPlaywright();
  const browser = await chromium.launch();
  const results = [];
  try {
    let state = null;
    if (opts.loginUrl || opts.formLogin) {
      state = await login(browser, opts);
      if (!state) {
        console.log('SELF-CHECK: unreachable (login did not succeed)');
        return 2;
      }
    }
    for (const shot of SHOTS) {
      try {
        results.push(await shoot(browser, shot, opts, state, outDir));
      } catch (error) {
        console.error(`WARN: ${shot.name} failed (${error.message}), retrying once`);
        results.push(await shoot(browser, shot, opts, state, outDir));
      }
    }
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    return 1;
  } finally {
    await browser.close();
  }

  for (const r of results) console.log(`${r.file}  ${r.finalUrl}`);
  console.log(`title: ${results[0].title}`);
  if (results.some((r) => r.loginPage)) {
    console.log('SELF-CHECK: unreachable (a shot landed on a login page)');
    return 2;
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}
