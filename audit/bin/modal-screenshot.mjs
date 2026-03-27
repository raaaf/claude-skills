#!/usr/bin/env node
import { chromium } from "playwright";
import fs from "fs";

const COOKIES_FILE = "/Users/rafael/Local Sites/rechnungs app/.claude/audit-cookies.json";
const SCREENSHOT_DIR = "/Users/rafael/Local Sites/rechnungs app/.claude/screenshots/main-69d9a3f";
const BASE_URL = "http://127.0.0.1:8001";

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });

  if (fs.existsSync(COOKIES_FILE)) {
    const cookies = JSON.parse(fs.readFileSync(COOKIES_FILE, "utf8"));
    await context.addCookies(cookies);
  }

  const page = await context.newPage();
  await page.goto(`${BASE_URL}/rechnungen`, { waitUntil: "networkidle", timeout: 30000 });
  await page.waitForTimeout(2000);

  // Get the first row and click it via JS dispatch (matching what Alpine does)
  const firstRow = page.locator("tr[role='button']").nth(1); // skip draft, use invoice 459
  
  // Use evaluate to dispatch the event the same way Alpine does
  await firstRow.evaluate((el) => {
    el.click();
  });

  // Wait longer for Livewire to process
  await page.waitForTimeout(4000);

  // Check if any modal or dialog appeared
  const dialogVisible = await page.locator('[role="dialog"], .modal, [x-show], [data-modal]').count();
  console.log("Dialog elements found:", dialogVisible);
  
  // List all visible elements with text
  const bodyHTML = await page.evaluate(() => document.body.innerHTML.length);
  console.log("Body HTML length:", bodyHTML);

  await page.screenshot({ path: `${SCREENSHOT_DIR}/invoice-detail-modal-desktop.png`, fullPage: false });
  console.log("Screenshot saved after click");

  await browser.close();
}

run().catch(err => { console.error(err); process.exit(1); });
