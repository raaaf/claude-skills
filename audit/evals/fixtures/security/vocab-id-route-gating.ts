import { Hono } from "hono";

const app = new Hono();

// Plus-gated: full catalog listing requires an active entitlement.
// This middleware is mounted on the EXACT path "/api/vocab" — Hono's
// app.use() only matches that literal path unless a wildcard is added.
app.use("/api/vocab", requirePlusEntitlement);

app.get("/api/vocab", async (c) => {
  const items = await vocabStore.listApproved();
  return c.json(items.map(toCatalogDto));
});

// BUG: /api/vocab/:id is a sibling of the gated path, not the same path, so
// the requirePlusEntitlement middleware above never runs for it. Any
// authenticated caller (including free-tier ones) can fetch the raw catalog
// item for any id, one at a time -> paywall bypass by enumerating ids.
app.get("/api/vocab/:id", async (c) => {
  const id = c.req.param("id");
  const item = await vocabStore.getById(id);
  if (!item) return c.json({ error: "not found" }, 404);
  return c.json(toCatalogDto(item));
});

// These stay intentionally free regardless of gating, so they are fine as-is.
app.get("/api/vocab/today", async (c) => c.json(await vocabStore.today()));
app.get("/api/vocab/sample", async (c) => c.json(await vocabStore.sampleFor(c)));

export default app;
