#!/usr/bin/env node
/**
 * capture-screenshots.js — Headless Chrome screenshot capture via Puppeteer.
 *
 * Usage:
 *   node capture-screenshots.js <config-json>
 *
 * Config JSON (stdin or file path):
 * {
 *   "baseUrl": "http://localhost:5173",
 *   "outputDir": "/path/to/.claude/screenshots/baseline",
 *   "themeMechanism": "prefers-color-scheme" | "data-theme" | "class-dark" | "auto",
 *   "routes": [
 *     { "slug": "homepage", "url": "/", "auth": false },
 *     { "slug": "blog-index", "url": "/blog", "auth": false }
 *   ],
 *   "auth": {
 *     "loginUrl": "/login",
 *     "username": "test@example.com",
 *     "password": "password",
 *     "usernameSelector": "input[name=email]",
 *     "passwordSelector": "input[name=password]",
 *     "submitSelector": "button[type=submit]"
 *   }
 * }
 *
 * Outputs screenshots to:
 *   <outputDir>/desktop/<slug>--light.png
 *   <outputDir>/desktop/<slug>--dark.png
 *   <outputDir>/mobile/<slug>--light.png
 *   <outputDir>/mobile/<slug>--dark.png
 *
 * Prints JSON manifest to stdout.
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const VIEWPORTS = {
  desktop: { width: 1280, height: 800, isMobile: false, hasTouch: false },
  mobile: { width: 375, height: 812, isMobile: true, hasTouch: true, deviceScaleFactor: 2 }
};

const THEMES = ['light', 'dark'];

// Theme switching strategies
const THEME_SCRIPTS = {
  'data-theme': {
    light: "document.documentElement.setAttribute('data-theme', 'light')",
    dark: "document.documentElement.setAttribute('data-theme', 'dark')"
  },
  'class-dark': {
    light: "document.documentElement.classList.remove('dark')",
    dark: "document.documentElement.classList.add('dark')"
  }
};

async function detectThemeMechanism(page) {
  return await page.evaluate(() => {
    // Check for data-theme attribute
    if (document.documentElement.hasAttribute('data-theme')) return 'data-theme';
    // Check for Tailwind dark class pattern
    if (document.documentElement.classList.contains('dark')) return 'class-dark';
    // Check CSS for data-theme selectors
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) {
          if (rule.selectorText && rule.selectorText.includes('[data-theme')) return 'data-theme';
          if (rule.selectorText && rule.selectorText.includes('.dark')) return 'class-dark';
        }
      } catch (e) { /* cross-origin stylesheet */ }
    }
    return 'prefers-color-scheme';
  });
}

async function setTheme(page, theme, mechanism) {
  if (mechanism === 'prefers-color-scheme') {
    await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: theme }]);
  } else if (THEME_SCRIPTS[mechanism]) {
    await page.evaluate(THEME_SCRIPTS[mechanism][theme]);
    // Also set media feature as backup
    await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: theme }]);
  }
  // Wait for theme transition
  await new Promise(r => setTimeout(r, 500));
}

async function authenticate(page, config) {
  if (!config.auth || !config.auth.loginUrl) return;

  const { loginUrl, username, password, usernameSelector, passwordSelector, submitSelector } = config.auth;

  await page.goto(`${config.baseUrl}${loginUrl}`, { waitUntil: 'networkidle2', timeout: 15000 });

  await page.waitForSelector(usernameSelector || 'input[name=email]', { timeout: 5000 });
  await page.type(usernameSelector || 'input[name=email]', username);
  await page.type(passwordSelector || 'input[name=password]', password);
  await page.click(submitSelector || 'button[type=submit]');

  // Wait for navigation after login
  await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 10000 }).catch(() => {});
  console.error('Auth: logged in successfully');
}

async function main() {
  // Read config
  const configPath = process.argv[2];
  if (!configPath) {
    console.error('Usage: node capture-screenshots.js <config.json>');
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const { baseUrl, outputDir, routes } = config;

  // Ensure output directories exist
  for (const vp of Object.keys(VIEWPORTS)) {
    fs.mkdirSync(path.join(outputDir, vp), { recursive: true });
  }

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--force-color-profile=srgb'
    ]
  });

  const page = await browser.newPage();

  // Authenticate if needed
  const needsAuth = routes.some(r => r.auth);
  if (needsAuth) {
    await authenticate(page, config);
  }

  // Detect theme mechanism on first page load
  let themeMechanism = config.themeMechanism || 'auto';
  if (themeMechanism === 'auto') {
    await page.setViewport(VIEWPORTS.desktop);
    await page.goto(`${baseUrl}${routes[0].url}`, { waitUntil: 'networkidle2', timeout: 15000 });
    themeMechanism = await detectThemeMechanism(page);
    console.error(`Theme mechanism detected: ${themeMechanism}`);
  }

  const manifest = {
    generated: new Date().toISOString(),
    base_url: baseUrl,
    theme_mechanism: themeMechanism,
    routes: {}
  };

  const totalScreenshots = routes.length * Object.keys(VIEWPORTS).length * THEMES.length;
  let count = 0;

  for (const route of routes) {
    const routeScreenshots = {};

    for (const [vpName, vpConfig] of Object.entries(VIEWPORTS)) {
      await page.setViewport(vpConfig);

      for (const theme of THEMES) {
        count++;
        const filename = `${route.slug}--${theme}.png`;
        const filePath = path.join(outputDir, vpName, filename);
        const relPath = `${vpName}/${filename}`;

        // Set theme before navigation for prefers-color-scheme
        if (themeMechanism === 'prefers-color-scheme') {
          await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: theme }]);
        }

        // Navigate
        await page.goto(`${baseUrl}${route.url}`, { waitUntil: 'networkidle2', timeout: 15000 });

        // Kill all animations and force everything visible
        await page.evaluate(() => {
          // Disable GSAP if present
          if (typeof gsap !== 'undefined') {
            gsap.globalTimeline.pause();
            gsap.globalTimeline.progress(1);
            // Kill all ScrollTrigger instances
            if (typeof ScrollTrigger !== 'undefined') {
              ScrollTrigger.getAll().forEach(st => {
                st.kill();
              });
            }
          }

          // Force all elements to be visible (undo animation initial states)
          // Note: we do NOT override transform — layout depends on it (e.g. horizontal galleries)
          const style = document.createElement('style');
          style.id = 'visual-baseline-overrides';
          style.textContent = `
            *, *::before, *::after {
              animation-duration: 0s !important;
              animation-delay: 0s !important;
              transition-duration: 0s !important;
              transition-delay: 0s !important;
              visibility: visible !important;
            }
          `;
          document.head.appendChild(style);

          // Set opacity to 1 on elements that have inline opacity < 1 (from GSAP)
          document.querySelectorAll('[style*="opacity"]').forEach(el => {
            el.style.opacity = '1';
          });
          // Also catch elements with opacity set via class
          document.querySelectorAll('*').forEach(el => {
            const computed = getComputedStyle(el);
            if (parseFloat(computed.opacity) < 1) {
              el.style.opacity = '1';
            }
          });
        });

        // Set theme after navigation for JS-based mechanisms
        await setTheme(page, theme, themeMechanism);

        // Wait for JS-rendered content to load (blog posts, dynamic content)
        await new Promise(r => setTimeout(r, 1000));

        // Wait for page content to be ready
        // SPA/dynamic pages may load content asynchronously
        if (route.waitFor) {
          // Route-specific wait selector
          try {
            await page.waitForSelector(route.waitFor, { timeout: 10000, visible: true });
          } catch (e) {
            console.error(`  Wait selector "${route.waitFor}" timeout for ${route.url}`);
          }
        } else {
          // Generic: wait for main content area to have substance
          try {
            await page.waitForFunction(
              () => {
                // Check for modal overlays (blog posts in SPA mode)
                const overlay = document.querySelector('.blog-post-overlay, .blog-post-modal');
                if (overlay) return true;
                // Check for article content
                const article = document.querySelector('article, .prose, main');
                return article && article.offsetHeight > 200;
              },
              { timeout: 8000 }
            );
          } catch (e) {
            // Timeout OK — page might be simple/short
          }
        }

        // Force all hidden containers visible (SPA hide-main pattern)
        await page.evaluate(() => {
          document.documentElement.style.removeProperty('--hide-main');

          // Check for fixed/absolute overlays that contain the real content
          // (e.g. blog post modals in SPA apps)
          const overlay = document.querySelector('.blog-post-overlay, [class*="overlay"][class*="post"], [class*="modal-overlay"]');
          if (overlay) {
            const cs = getComputedStyle(overlay);
            if (cs.position === 'fixed' || cs.position === 'absolute') {
              // Convert overlay to static block so fullPage screenshot captures it
              overlay.style.position = 'static';
              overlay.style.width = '100%';
              overlay.style.height = 'auto';
              overlay.style.overflow = 'visible';
              overlay.style.zIndex = 'auto';
              // Hide ALL sibling elements so only the overlay content shows
              const parent = overlay.parentElement;
              if (parent) {
                Array.from(parent.children).forEach(el => {
                  if (el !== overlay) {
                    el.style.display = 'none';
                  }
                });
              }
            }
          } else {
            // No overlay — just ensure main containers are visible
            document.querySelectorAll('#app, main, .app-container').forEach(el => {
              if (getComputedStyle(el).display === 'none') {
                el.style.display = 'block';
              }
            });
          }
        });

        // Final settle
        await new Promise(r => setTimeout(r, 500));

        // Take screenshot
        await page.screenshot({
          path: filePath,
          fullPage: true,
          type: 'png'
        });

        routeScreenshots[`${vpName}-${theme}`] = relPath;
        console.error(`[${count}/${totalScreenshots}] ${relPath}`);
      }
    }

    manifest.routes[route.slug] = {
      url: route.url,
      auth: route.auth || false,
      view_files: route.view_files || [],
      screenshots: routeScreenshots,
      captured_at: new Date().toISOString()
    };
  }

  await browser.close();

  // Print manifest to stdout
  console.log(JSON.stringify(manifest, null, 2));
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
