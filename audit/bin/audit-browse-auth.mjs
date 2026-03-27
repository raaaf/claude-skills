import { chromium } from "playwright";

const VIEWPORTS = {
  desktop: { width: 1280, height: 800 },
  tablet: { width: 768, height: 1024 },
  mobile: { width: 375, height: 812 },
};

const BASE_URL = "http://127.0.0.1:8000";
const LOGIN_URL = `${BASE_URL}/login`;
const EMAIL = "host@example.com";
const PASSWORD = "password";

const PAGES = [
  { url: `${BASE_URL}/events/sommerparty-2026/manage/edit`, prefix: process.argv[2] + "/event-edit" },
  { url: `${BASE_URL}/g/yoga-dienstag/edit/settings`, prefix: process.argv[2] + "/group-edit-settings" },
];

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();

// Login once
const loginPage = await context.newPage();
await loginPage.goto(LOGIN_URL, { waitUntil: "networkidle", timeout: 30000 });
await loginPage.fill('input[name="email"]', EMAIL);
await loginPage.fill('input[name="password"]', PASSWORD);
await loginPage.click('button[type="submit"]');
await loginPage.waitForLoadState("networkidle");
console.log("Logged in, current URL:", loginPage.url());
await loginPage.close();

// Screenshot each page
for (const { url, prefix } of PAGES) {
  for (const [name, viewport] of Object.entries(VIEWPORTS)) {
    const page = await context.newPage();
    await page.setViewportSize(viewport);
    await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
    const path = `${prefix}-${name}.png`;
    await page.screenshot({ path, fullPage: false });
    console.log(`Screenshot saved: ${path}`);
    await page.close();
  }
}

await browser.close();
