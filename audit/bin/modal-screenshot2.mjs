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

  // Click the "Gesendet" invoice (row with status Versendet = invoice 459 which is Storniert now)
  // Let's click the "Bezahlt" row (458) for best button options
  const rows = page.locator("tr[role='button']");
  const count = await rows.count();
  console.log("Row count:", count);

  // Click the last row (Bezahlt = 458)
  await rows.nth(count - 1).evaluate(el => el.click());
  await page.waitForTimeout(4000);

  // List all buttons in the modal
  const buttons = await page.locator("button:visible").allTextContents();
  console.log("Visible buttons:", JSON.stringify(buttons));

  // Take modal screenshot
  await page.screenshot({ path: `${SCREENSHOT_DIR}/invoice-detail-modal-bezahlt-desktop.png`, fullPage: false });
  console.log("Bezahlt modal screenshot saved");

  // Close and reopen with the "Gesendet" invoice (second row = index 1)
  await page.keyboard.press("Escape");
  await page.waitForTimeout(1000);

  // Click the second row (index 1 = Storniert 459) — let's try index 0 first (Entwurf)
  // Actually let's look for a row that has "Versenden" button — click the draft row
  await rows.nth(0).evaluate(el => el.click());
  await page.waitForTimeout(4000);

  const draftButtons = await page.locator("button:visible").allTextContents();
  console.log("Draft modal buttons:", JSON.stringify(draftButtons));
  await page.screenshot({ path: `${SCREENSHOT_DIR}/invoice-detail-modal-entwurf-desktop.png`, fullPage: false });
  console.log("Entwurf modal screenshot saved");

  // Try to click "Finalisieren" or "Versenden" button
  for (const btn of await page.locator("button:visible").all()) {
    const text = (await btn.textContent()).trim();
    console.log("Button text:", JSON.stringify(text));
    if (/finalisi|versend|PDF/i.test(text)) {
      console.log("Clicking:", text);
      await btn.click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${SCREENSHOT_DIR}/nested-modal-desktop.png`, fullPage: false });
      console.log("Nested modal screenshot saved");
      break;
    }
  }

  await browser.close();
}

run().catch(err => { console.error(err); process.exit(1); });
