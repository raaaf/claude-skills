// Fixture: a Hono dashboard's first-run TOTP setup. POST /setup stores a
// pending secret and binds it to the starting browser with a cookie;
// GET /setup/confirm shows the secret as a QR code and must only do that for
// the browser that started setup.
//
// Real-world origin: henry-companion dashboard, 2026-09. The cookie binding was
// added as a fix, and the next two audit rounds each found a new bug in the
// same endpoint the fix had introduced.
import { Hono } from "hono";
import { getCookie, setCookie } from "hono/cookie";

const settings = new Map<string, string>();
const app = new Hono();

app.post("/setup", (c) => {
  const secret = crypto.randomUUID();
  const token = crypto.randomUUID();
  settings.set("pending_totp", secret);
  settings.set("setup_token", token);
  settings.set("setup_expires", String(Date.now() + 10 * 60_000));
  setCookie(c, "henry_setup", token, { httpOnly: true, sameSite: "Strict" });
  return c.redirect("/setup/confirm");
});

app.get("/setup/confirm", (c) => {
  const cookie = getCookie(c, "henry_setup");
  // BUG 1: without the cookie this redirects to GET /setup, whose handler
  // below sends every visitor with a pending secret straight back here.
  // A browser without the cookie loops forever.
  if (!cookie) return c.redirect("/setup");
  // BUG 2: only checks that SOME cookie exists and never compares it with
  // setup_token or checks setup_expires, so any browser that sets an
  // arbitrary henry_setup cookie sees the pending TOTP secret.
  return c.text(`Scan: ${settings.get("pending_totp")}`);
});

app.get("/setup", (c) => {
  if (settings.has("pending_totp")) return c.redirect("/setup/confirm");
  return c.text("Start setup");
});

export default app;
