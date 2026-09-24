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

// GPU-accelerated rasterization is a known source of run-to-run sub-pixel
// anti-aliasing jitter in headless Chromium screenshots (a handful of text
// edge pixels rounding differently between runs, nothing to do with app
// state). Forcing software rendering makes glyph rasterization deterministic.
test.use({ launchOptions: { args: ['--disable-gpu', '--force-color-profile=srgb'] } });

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

// Capture efficiency (plan section, revised 2026-09-24 after the user
// reported earlier runs overloading the machine): a `setViewportSize` or a
// class/cookie theme toggle is a client-side change, not a navigation, so
// two animation frames is enough settle time instead of a full page load.
async function waitTwoRaf(page) {
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

// State axes "empty": a role can have a second demo login in
// config.demo_logins_empty (a per-role account seeded with no data, e.g.
// onboarding completed but zero projects/entries); falls back to the
// regular (filled) login when no empty-state login is configured for that
// role, so an entry that lists "empty" without an empty login just
// captures the same account twice under different state labels instead of
// failing.
async function loginAs(page, role, state) {
  if (role === 'guest') return;
  const emptyLogins = config.demo_logins_empty || {};
  const usingEmptyLogin = state === 'empty' && emptyLogins[role];
  const email = usingEmptyLogin || (config.demo_logins && config.demo_logins[role]);
  // The empty-state account is frequently a project's own pre-existing
  // secondary test user (not created by ScreensDemoSeeder), so its
  // password can differ from the primary demo_password.
  const password = (usingEmptyLogin && config.demo_password_empty) || config.demo_password;
  if (!email || !password) {
    throw new Error(`no demo login configured for role "${role}" (config.demo_logins / config.demo_password)`);
  }
  await page.goto(`${BASE_URL}/login`);
  await page.fill('input[name=email]', email);
  await page.fill('input[name=password]', password);
  await submitScopedForm(page);
}

// Submits by pressing Enter in the form's last field rather than clicking
// the submit button: a bare `button[type=submit]` click can match/land on
// an unrelated element (e.g. a language switcher earlier in the DOM) or,
// verified against this project's own `<x-button>` component, silently
// fail to fire the form's `wire:submit.prevent` handler at all (no
// network request), while Enter in the last field reliably submits the
// same form. `lastFieldSelector` defaults to the login form's password
// field; submitErrorState passes the last entry.error_fill selector so a
// multi-field form (e.g. register's password_confirmation) submits from
// the field a real user would actually be on when they hit Enter.
async function submitScopedForm(page, lastFieldSelector = 'input[name=password]') {
  await page.locator(lastFieldSelector).press('Enter');
  await page.waitForLoadState('networkidle');
  // A small settle wait after the Livewire response: networkidle resolves
  // once the request finishes, but the client-side DOM morph that renders
  // the validation error happens a tick after that.
  await page.waitForTimeout(300);
}

// State axis "error": fills entry.error_fill ({selector, value} pairs,
// manifest-driven so this stays generic per repo CLAUDE.md "every
// generated driver must read the manifest at runtime instead of
// hard-coding entries") and submits by pressing Enter in the LAST listed
// field, so the page renders its own server-side validation error state
// instead of a synthetic one.
async function submitErrorState(page, entry) {
  const fields = entry.error_fill || [];
  for (const field of fields) {
    await page.fill(field.selector, field.value);
  }
  const lastSelector = fields.length ? fields[fields.length - 1].selector : 'input[name=password]';
  await submitScopedForm(page, lastSelector);
}

const viewports = (config.axes && config.axes.viewports && config.axes.viewports.web) || ['1440x900'];
const themes = (config.axes && config.axes.themes) || ['light'];
const primaryLocale = (config.axes && config.axes.locales && config.axes.locales.primary) || 'en';

// Capture efficiency (plan section, revised 2026-09-24 after the user
// reported earlier runs overloading the machine): one navigation per
// (entry, state, role) instead of one per (entry, state, role, viewport,
// theme). All device-class x theme shots are taken inside that same page by
// switching viewport (setViewportSize) and theme (emulateMedia + the
// project's own client-side dark-mode toggle) without reloading; only an
// entry marked `reload_per_viewport: true` in the manifest (verified by an
// ImageMagick compare between the two capture paths, screens/references
// platform-web.md) gets a fresh `page.goto` per viewport.
async function applyMaskAndErrorState(page, entry, state) {
  if (state === 'error') {
    await submitErrorState(page, entry);
  }
  for (const selector of entry.mask || []) {
    await page.locator(selector).evaluateAll((els) => els.forEach((el) => { el.style.visibility = 'hidden'; }));
  }
}

for (const entry of manifest.entries || []) {
  const states = entry.states && entry.states.length ? entry.states : ['filled'];
  const roles = entry.roles && entry.roles.length ? entry.roles : ['guest'];

  for (const state of states) {
    for (const role of roles) {
      test(`${entry.id} ${state} ${role}`, async ({ browser }) => {
        const urlHost = new URL(BASE_URL).hostname;
        const context = await browser.newContext({
          // Catalog captures use the primary locale only (plan's State
          // axes: locale). Without this, a guest-facing page whose locale
          // middleware reads Accept-Language (no session yet) renders in
          // the browser's default language instead.
          locale: `${primaryLocale}-${primaryLocale.toUpperCase()}`,
        });
        // External hosts blocked (plan's "Dynamic content" edge case): allowlist
        // localhost/127.0.0.1 only, abort everything else.
        await context.route('**/*', (route) => {
          const url = new URL(route.request().url());
          if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') return route.continue();
          return route.abort();
        });

        // Applied before any navigation (init script + reduced-motion media
        // emulation, not just a post-render style tag): a JS-driven mount
        // animation (e.g. a number count-up) that starts before the style
        // tag lands gets frozen mid-frame by the fixed clock below and
        // screenshots as visibly garbled overlapping digits. Appended
        // synchronously (not on DOMContentLoaded) so the override is
        // guaranteed to land before any of the page's own scripts run,
        // including deferred bundles (Alpine) that mount and start their
        // own x-transition before DOMContentLoaded fires: a
        // DOMContentLoaded-gated style tag lost that race intermittently,
        // leaving a handful of sub-pixel anti-aliasing diffs around fading
        // nav-scroll-gradient overlays.
        await context.addInitScript((css) => {
          const style = document.createElement('style');
          style.textContent = css;
          (document.head || document.documentElement).appendChild(style);
        }, DISABLE_ANIMATIONS_CSS);

        const page = await context.newPage();
        await page.emulateMedia({ reducedMotion: 'reduce' });
        await page.clock.setFixedTime(FIXED_TIME);
        await loginAs(page, role, state);

        await page.goto(`${BASE_URL}${entry.reach}`);
        await page.waitForLoadState('networkidle');
        if (entry.ready) {
          await page.waitForSelector(entry.ready, { timeout: 15000 });
        }
        await applyMaskAndErrorState(page, entry, state);

        for (const viewport of viewports) {
          if (entry.reload_per_viewport) {
            await page.setViewportSize(parseViewport(viewport));
            await page.goto(`${BASE_URL}${entry.reach}`);
            await page.waitForLoadState('networkidle');
            if (entry.ready) {
              await page.waitForSelector(entry.ready, { timeout: 15000 });
            }
            await applyMaskAndErrorState(page, entry, state);
          } else {
            await page.setViewportSize(parseViewport(viewport));
            await waitTwoRaf(page);
            await page.waitForLoadState('networkidle');
          }

          for (const theme of themes) {
            // zeit's dark mode is not prefers-color-scheme-driven: every
            // layout reads a `dark_mode` cookie server-side (`session('dark_mode',
            // request()->cookie('dark_mode') === 'true')`) to decide the
            // `dark` class on <html>. A cookie only takes effect on the NEXT
            // navigation, so toggling it without a reload additionally
            // drives the client-side class directly (the same class the
            // server would have rendered), matching the project's own
            // Tailwind `dark:` variant. colorScheme is still emulated for
            // any OS-level media-query fallback elsewhere.
            await page.emulateMedia({ colorScheme: theme === 'dark' ? 'dark' : 'light' });
            await context.addCookies([{
              name: 'dark_mode', value: theme === 'dark' ? 'true' : 'false',
              domain: urlHost, path: '/',
            }]);
            await page.evaluate((isDark) => {
              document.documentElement.classList.toggle('dark', isDark);
            }, theme === 'dark');
            await waitTwoRaf(page);

            const filename = `${entry.id}__${state}__${role}__${viewport}__${theme}.png`;
            await page.screenshot({ path: join(OUT_DIR, filename), fullPage: true });
          }
        }

        await context.close();
      });
    }
  }
}
