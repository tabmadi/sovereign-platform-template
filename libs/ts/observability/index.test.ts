// These tests pin the browser fingerprint's rules, per ADR-0503.
import { describe, expect, test as it } from "vitest";

import { appFrames, fingerprint, normalise } from "./index";

const HEX8 = /^[0-9a-f]{8}$/u;

describe("normalise", () => {
  it("an entity id becomes a placeholder", () => {
    expect(normalise("order order_01kztmx9e0fq1r13w5d1aerqw6 not found")).toBe(
      "order order_<x> not found",
    );
  });

  it("digit runs become a placeholder", () => {
    expect(normalise("retry 3 of 5")).toBe("retry <n> of <n>");
  });

  // Words that are also hex are words, not values.
  it("short words survive", () => {
    expect(normalise("deadlock detected")).toBe("deadlock detected");
    expect(normalise("add failed")).toBe("add failed");
  });

  it("a message with no varying part is unchanged", () => {
    expect(normalise("the pool is closed")).toBe("the pool is closed");
  });
});

describe("appFrames", () => {
  const stack = [
    "Error: boom",
    "    at placeOrder (https://app.example.com/_next/static/chunks/page.js:12:34)",
    "    at onSubmit (https://app.example.com/_next/static/chunks/node_modules/react-dom.js:9:1)",
    "    at handler (https://app.example.com/_next/static/chunks/panel.js:88:2)",
  ].join("\n");

  it("keeps first-party frames in order", () => {
    expect(appFrames(stack)).toEqual(["placeOrder", "handler"]);
  });

  it("drops vendor frames", () => {
    expect(appFrames(stack)).not.toContain("onSubmit");
  });

  it("an absent stack yields no frames", () => {
    expect(appFrames(undefined)).toEqual([]);
  });
});

describe("fingerprint", () => {
  const base = { name: "TypeError", message: "order order_1 not found", stack: "at f (a.js:1:1)" };

  it("is stable for the same fault", () => {
    expect(fingerprint(base)).toBe(fingerprint({ ...base }));
  });

  // This is the purpose of the normaliser: an id must not make a new fault.
  it("ignores the varying part of the message", () => {
    const other = { ...base, message: "order order_2 not found" };
    expect(fingerprint(other)).toBe(fingerprint(base));
  });

  it("separates distinct faults", () => {
    const other = { ...base, message: "the pool is closed" };
    expect(fingerprint(other)).not.toBe(fingerprint(base));
  });

  // A line-number change is a cosmetic edit and must not change the fault.
  it("ignores line and column numbers", () => {
    const moved = { ...base, stack: "at f (a.js:99:7)" };
    expect(fingerprint(moved)).toBe(fingerprint(base));
  });

  it("is short and hex", () => {
    expect(fingerprint(base)).toMatch(HEX8);
  });
});
