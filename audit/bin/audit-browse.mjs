#!/usr/bin/env node

/**
 * audit-browse.mjs — Headless screenshot tool for audit design verification.
 *
 * Usage:
 *   node audit-browse.mjs screenshot <url> <output-path> [--viewport WxH] [--fullpage] [--cookies <path>]
 *   node audit-browse.mjs responsive <url> <output-prefix> [--fullpage] [--cookies <path>]
 *   node audit-browse.mjs login <login-url> <cookies-output-path> [--auth <auth-json-path>]
 *     Without --auth: opens a visible browser for manual login, saves cookies on close.
 *     With --auth: reads { url, usernameSelector, passwordSelector, username, password, submitSelector }
 *                  and logs in headlessly, then saves cookies.
 *
 * Examples:
 *   node audit-browse.mjs screenshot http://localhost:8000 /tmp/home.png --fullpage --cookies /tmp/cookies.json
 *   node audit-browse.mjs responsive http://localhost:8000 /tmp/home --fullpage --cookies /tmp/cookies.json
 *   node audit-browse.mjs login http://localhost:8000/login /tmp/cookies.json
 *   node audit-browse.mjs login http://localhost:8000/login /tmp/cookies.json --auth /path/to/auth.json
 */

import { chromium } from "playwright";
import fs from "fs";

const VIEWPORTS = {
  desktop: { width: 1280, height: 800 },
  tablet: { width: 768, height: 1024 },
  mobile: { width: 375, height: 812 },
};

async function loadCookies(context, cookiesPath) {
  if (cookiesPath && fs.existsSync(cookiesPath)) {
    try {
      const cookies = JSON.parse(fs.readFileSync(cookiesPath, "utf8"));
      await context.addCookies(cookies);
    } catch (err) {
      console.warn(`Warning: Could not load cookies from ${cookiesPath}: ${err.message}`);
    }
  }
}

async function takeScreenshot(url, outputPath, viewport = VIEWPORTS.desktop, fullPage = false, cookiesPath = null) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport });
  await loadCookies(context, cookiesPath);
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
    await page.screenshot({ path: outputPath, fullPage });
    console.log(`Screenshot saved: ${outputPath}`);
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

async function takeResponsive(url, outputPrefix, fullPage = false, cookiesPath = null) {
  const browser = await chromium.launch({ headless: true });
  try {
    for (const [name, viewport] of Object.entries(VIEWPORTS)) {
      const context = await browser.newContext({ viewport });
      await loadCookies(context, cookiesPath);
      const page = await context.newPage();
      await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
      const outputPath = `${outputPrefix}-${name}.png`;
      await page.screenshot({ path: outputPath, fullPage });
      console.log(`Screenshot saved: ${outputPath}`);
      await context.close();
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

async function loginAutomatic(loginUrl, cookiesOutputPath, authConfig) {
  const {
    usernameSelector = 'input[type="email"], input[name="email"], input[name="username"], input[name="login"]',
    passwordSelector = 'input[type="password"]',
    submitSelector = 'button[type="submit"], input[type="submit"]',
    username,
    password,
  } = authConfig;

  console.log(`Logging in headlessly at: ${loginUrl}`);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto(loginUrl, { waitUntil: "networkidle", timeout: 30000 });
    await page.fill(usernameSelector, username);
    await page.fill(passwordSelector, password);
    await Promise.all([
      page.waitForURL((url) => !url.href.includes(new URL(loginUrl).pathname), { timeout: 15000 }).catch(() => {}),
      page.click(submitSelector),
    ]);

    const cookies = await context.cookies();
    fs.writeFileSync(cookiesOutputPath, JSON.stringify(cookies, null, 2));
    console.log(`Cookies saved to: ${cookiesOutputPath} (${cookies.length} cookies)`);
  } catch (err) {
    console.error(`Login error: ${err.message}`);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

async function loginManual(loginUrl, cookiesOutputPath) {
  console.log(`Opening browser for manual login at: ${loginUrl}`);
  console.log(`Log in, then close the browser window — cookies will be saved automatically.`);

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto(loginUrl, { waitUntil: "networkidle", timeout: 30000 });

  const saveCookies = async () => {
    try {
      const cookies = await context.cookies();
      fs.writeFileSync(cookiesOutputPath, JSON.stringify(cookies, null, 2));
      console.log(`Cookies saved to: ${cookiesOutputPath} (${cookies.length} cookies)`);
    } catch {
      // context already closed, ignore
    }
  };

  await new Promise((resolve) => {
    browser.on("disconnected", resolve);
    page.on("close", resolve);
  });

  await saveCookies();
  try { await browser.close(); } catch { /* already closed */ }
}

// Parse args
const [, , command, ...args] = process.argv;

if (command === "screenshot") {
  const url = args[0];
  const outputPath = args[1];
  const vpIdx = args.indexOf("--viewport");
  const fullPage = args.includes("--fullpage");
  const cookiesIdx = args.indexOf("--cookies");
  const cookiesPath = cookiesIdx !== -1 ? args[cookiesIdx + 1] : null;
  let viewport = VIEWPORTS.desktop;
  if (vpIdx !== -1 && args[vpIdx + 1]) {
    const [w, h] = args[vpIdx + 1].split("x").map(Number);
    viewport = { width: w, height: h };
  }
  if (!url || !outputPath) {
    console.error("Usage: audit-browse.mjs screenshot <url> <output-path> [--viewport WxH] [--fullpage] [--cookies <path>]");
    process.exit(1);
  }
  await takeScreenshot(url, outputPath, viewport, fullPage, cookiesPath);

} else if (command === "responsive") {
  const url = args[0];
  const outputPrefix = args[1];
  const fullPage = args.includes("--fullpage");
  const cookiesIdx = args.indexOf("--cookies");
  const cookiesPath = cookiesIdx !== -1 ? args[cookiesIdx + 1] : null;
  if (!url || !outputPrefix) {
    console.error("Usage: audit-browse.mjs responsive <url> <prefix> [--fullpage] [--cookies <path>]");
    process.exit(1);
  }
  await takeResponsive(url, outputPrefix, fullPage, cookiesPath);

} else if (command === "login") {
  const loginUrl = args[0];
  const cookiesOutputPath = args[1];
  const authIdx = args.indexOf("--auth");
  if (!loginUrl || !cookiesOutputPath) {
    console.error("Usage: audit-browse.mjs login <login-url> <cookies-output-path> [--auth <auth-json-path>]");
    process.exit(1);
  }
  if (authIdx !== -1 && args[authIdx + 1]) {
    const authConfig = JSON.parse(fs.readFileSync(args[authIdx + 1], "utf8"));
    await loginAutomatic(loginUrl, cookiesOutputPath, authConfig);
  } else {
    await loginManual(loginUrl, cookiesOutputPath);
  }

} else {
  console.error("Commands: screenshot, responsive, login");
  console.error("  screenshot <url> <path> [--viewport WxH] [--fullpage] [--cookies <path>]");
  console.error("  responsive <url> <prefix> [--fullpage] [--cookies <path>]");
  console.error("  login <login-url> <cookies-output-path> [--auth <auth-json-path>]");
  process.exit(1);
}
