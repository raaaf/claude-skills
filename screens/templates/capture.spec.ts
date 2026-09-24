// capture.spec.ts: generic Playwright driver for /screens (screens/references/platform-web.md).
//
// Copied verbatim into `<project>/.screens/web/capture.spec.ts` by the Phase 2 scaffold executor
// (repo CLAUDE.md "Reviewer: every generated driver must read the manifest at runtime instead of
// hard-coding entries" -- this file never hard-codes a project's views). Reads
// `.screens/config.json` and `.screens/manifest.json` from `process.cwd()` at test-collection time,
// so the same file works unmodified for every Laravel/web pilot.
//
// Invocation: `npx playwright test .screens/web/capture.spec.ts --workers=4 [--grep <pattern>]`
// from the project root, after `screens.mjs up --platform web` succeeded.

import { test } from '@playwright/test';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const config = JSON.parse(readFileSync(join(ROOT, '.screens/config.json'), 'utf8'));
const manifest = JSON.parse(readFileSync(join(ROOT, '.screens/manifest.json'), 'utf8'));

const BASE_URL = process.env.SCREENS_BASE_URL || `http://127.0.0.1:${config.web.port}`;
const OUT_DIR = join(ROOT, '.screens/.incoming/web');
mkdirSync(OUT_DIR, { recursive: true });

// Fixed clock (topf-secret's `-ScreensFixedDate` convention, web equivalent) plus disabled
// animations/transitions and a localhost-only route allowlist make an identical render produce
// identical PNG bytes (plan's Approach: no pixel decoder needed).
const FIXED_TIME = '2026-05-12T09:41:00+02:00';
const DISABLE_ANIMATIONS_CSS = '*, *::before, *::after { animation-duration: 0s !important; animation-delay: 0s !important; transition-duration: 0s !important; }';

function parseViewport(spec) {
  const [width, height] = spec.split('x').map(Number);
  return { width, height };
}

async function loginAs(page, role) {
  if (role === 'guest') return;
  const email = config.demo_logins && config.demo_logins[role];
  const password = config.demo_password;
  if (!email || !password) {
    throw new Error(`no demo login configured for role "${role}" (config.demo_logins / config.demo_password)`);
  }
  await page.goto(`${BASE_URL}/login`);
  await page.fill('input[name=email]', email);
  await page.fill('input[name=password]', password);
  // Scoped to the login form's own submit button: a bare `button[type=submit]`
  // can match an unrelated form earlier in the DOM (e.g. a language switcher),
  // submitting the wrong form silently instead of logging in.
  await page.locator('form').filter({ has: page.locator('input[name=email]') })
    .locator('button[type=submit]').click();
  await page.waitForLoadState('networkidle');
}

const viewports = (config.axes && config.axes.viewports && config.axes.viewports.web) || ['1440x900'];
const themes = (config.axes && config.axes.themes) || ['light'];
const primaryLocale = (config.axes && config.axes.locales && config.axes.locales.primary) || 'en';

for (const entry of manifest.entries || []) {
  const states = entry.states && entry.states.length ? entry.states : ['filled'];
  const roles = entry.roles && entry.roles.length ? entry.roles : ['guest'];

  for (const state of states) {
    for (const role of roles) {
      for (const viewport of viewports) {
        for (const theme of themes) {
          test(`${entry.id} ${state} ${role} ${viewport} ${theme}`, async ({ browser }) => {
            const context = await browser.newContext({
              viewport: parseViewport(viewport),
              colorScheme: theme === 'dark' ? 'dark' : 'light',
              // Catalog captures use the primary locale only (plan's State
              // axes: locale). Without this, a guest-facing page whose
              // locale middleware reads Accept-Language (no session yet)
              // renders in the browser's default language instead.
              locale: `${primaryLocale}-${primaryLocale.toUpperCase()}`,
            });
            // External hosts blocked (plan's "Dynamic content" edge case): allowlist
            // localhost/127.0.0.1 only, abort everything else.
            await context.route('**/*', (route) => {
              const url = new URL(route.request().url());
              if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') return route.continue();
              return route.abort();
            });

            // Applied before any navigation (init script + reduced-motion
            // media emulation, not just a post-render style tag): a
            // JS-driven mount animation (e.g. a number count-up) that
            // starts before the style tag lands gets frozen mid-frame by
            // the fixed clock below and screenshots as visibly garbled
            // overlapping digits.
            await context.addInitScript((css) => {
              document.addEventListener('DOMContentLoaded', () => {
                const style = document.createElement('style');
                style.textContent = css;
                document.head.appendChild(style);
              });
            }, DISABLE_ANIMATIONS_CSS);

            const page = await context.newPage();
            await page.emulateMedia({ reducedMotion: 'reduce' });
            await page.clock.setFixedTime(FIXED_TIME);
            await loginAs(page, role);

            await page.goto(`${BASE_URL}${entry.reach}`);
            await page.waitForLoadState('networkidle');
            if (entry.ready) {
              await page.waitForSelector(entry.ready, { timeout: 15000 });
            }

            for (const selector of entry.mask || []) {
              await page.locator(selector).evaluateAll((els) => els.forEach((el) => { el.style.visibility = 'hidden'; }));
            }

            const filename = `${entry.id}__${state}__${role}__${viewport}__${theme}.png`;
            await page.screenshot({ path: join(OUT_DIR, filename), fullPage: true });
            await context.close();
          });
        }
      }
    }
  }
}
