import { describe, expect, test } from "bun:test";
import { designOnly, resolveFixtureMode } from "./mode";

describe("the production guard of fixture mode", () => {
  test("a production build with fixtures fails", () => {
    expect(() => resolveFixtureMode("1", undefined, "production")).toThrow("NEXT_PUBLIC_FIXTURES");
  });

  test("a production build with fixtures and a design-build value other than 1 fails", () => {
    expect(() => resolveFixtureMode("1", "true", "production")).toThrow("NEXT_PUBLIC_FIXTURES");
  });

  test("the design build is a production build with fixtures on", () => {
    expect(resolveFixtureMode("1", "1", "production")).toBe(true);
  });

  test("a production build without fixtures reads the services", () => {
    expect(resolveFixtureMode(undefined, undefined, "production")).toBe(false);
    expect(resolveFixtureMode(undefined, "1", "production")).toBe(false);
  });

  test("next dev with fixtures needs no design-build switch", () => {
    expect(resolveFixtureMode("1", undefined, "development")).toBe(true);
  });
});

describe("a design-only page", () => {
  test("renders in fixture mode", () => {
    expect(() => designOnly(true)).not.toThrow();
  });

  test("is not found outside fixture mode", () => {
    expect(() => designOnly(false)).toThrow();
  });
});
