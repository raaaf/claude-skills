import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";

// Pre-existing, untouched by the diff. THIS is a guard test: it walks the whole
// directory and enforces a convention across every file it finds.
test("every component file is kebab-case", () => {
  const offenders = readdirSync("src/components")
    .filter((name) => !/^[a-z0-9-]+\.vue$/.test(name));

  expect(offenders).toEqual([]);
});
