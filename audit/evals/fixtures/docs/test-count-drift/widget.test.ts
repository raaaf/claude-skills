import { describe, expect, test } from "bun:test";

function label(name: string): string {
  return name.trim().toLowerCase();
}

describe("label", () => {
  test("lowercases", () => {
    expect(label("Foo")).toBe("foo");
  });

  test("trims", () => {
    expect(label("  foo ")).toBe("foo");
  });

  test("keeps inner spaces", () => {
    expect(label("foo bar")).toBe("foo bar");
  });

  // Added by a later fix wave; the README count above was never bumped.
  test("empty stays empty", () => {
    expect(label("")).toBe("");
  });

  test("umlauts survive", () => {
    expect(label("Grün")).toBe("grün");
  });
});
