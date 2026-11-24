import { describe, expect, test as it } from "vitest";
import { designOnly, resolveFixtureMode } from "./mode";

describe("the production guard of fixture mode", () => {
  it("a production build with fixtures fails", () => {
    expect(() => resolveFixtureMode("1", undefined, "production")).toThrow("NEXT_PUBLIC_FIXTURES");
  });

  it("a production build with fixtures and a design-build value other than 1 fails", () => {
    expect(() => resolveFixtureMode("1", "true", "production")).toThrow("NEXT_PUBLIC_FIXTURES");
  });

  it("the design build is a production build with fixtures on", () => {
    expect(resolveFixtureMode("1", "1", "production")).toBe(true);
  });

  it("a production build without fixtures reads the services", () => {
    expect(resolveFixtureMode(undefined, undefined, "production")).toBe(false);
    expect(resolveFixtureMode(undefined, "1", "production")).toBe(false);
  });

  it("next dev with fixtures needs no design-build switch", () => {
    expect(resolveFixtureMode("1", undefined, "development")).toBe(true);
  });
});

describe("a design-only page", () => {
  it("renders in fixture mode", () => {
    expect(() => designOnly(true)).not.toThrow();
  });

  it("is not found outside fixture mode", () => {
    expect(() => designOnly(false)).toThrow();
  });
});
