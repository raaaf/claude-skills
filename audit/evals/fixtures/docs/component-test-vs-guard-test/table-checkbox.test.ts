import { expect, test } from "bun:test";
import { render } from "./render";

// Added in this diff. Renders one component, asserts its own markup.
test("input carries an explicit hit area size", () => {
  const html = render("table-checkbox", { value: "1" });

  expect(html).toMatch(/<input[^>]*-inset-2/);
  expect(html).toMatch(/<input[^>]*size-8/);
});
