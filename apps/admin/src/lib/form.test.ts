import { describe, expect, it } from "vitest";
import { bodyFrom, fillPath, read, recordPath, rowsOf, show } from "./form";
import type { Field } from "./manifest";

describe("form helpers", () => {
  it("a dotted name reads a nested value", () => {
    expect(read({ price: { amount: "42.00" } }, "price.amount")).toBe("42.00");
    expect(read({ price: null }, "price.amount")).toBeUndefined();
  });

  it("a path parameter is escaped, and a missing one is an error", () => {
    expect(fillPath("/charges/{id}/refund", { id: "a b" })).toBe("/charges/a%20b/refund");
    expect(() => fillPath("/charges/{id}", {})).toThrow("missing path parameter id");
    expect(recordPath("/orgs/{orgId}", "o1")).toBe("/orgs/o1");
  });

  it("a money field becomes a nested amount and currency", () => {
    const fields: Field[] = [
      { name: "name", label: "Name", kind: "string" },
      { name: "price.amount", label: "Price", kind: "string" },
      { name: "price.currency", label: "Currency", kind: "string" },
    ];
    const form = new FormData();
    form.set("name", "widget");
    form.set("price.amount", "42.00");
    form.set("price.currency", "EUR");
    expect(bodyFrom(fields, form)).toEqual({
      name: "widget",
      price: { amount: "42.00", currency: "EUR" },
    });
  });

  it("an unchecked switch is false, and an empty number is left out", () => {
    const fields: Field[] = [
      { name: "operator", label: "Operator", kind: "boolean" },
      { name: "limit", label: "Limit", kind: "integer" },
    ];
    expect(bodyFrom(fields, new FormData())).toEqual({ operator: false });
    const form = new FormData();
    form.set("limit", "x");
    expect(() => bodyFrom(fields, form)).toThrow("Limit is not a number");
  });

  it("rows come from a bare array or an items array", () => {
    expect(rowsOf([{ id: "1" }])).toEqual([{ id: "1" }]);
    expect(rowsOf({ items: [{ id: "2" }] })).toEqual([{ id: "2" }]);
    expect(rowsOf({})).toEqual([]);
  });

  it("a cell shows text for every value", () => {
    expect(show(undefined)).toBe("");
    expect(show(true)).toBe("true");
    expect(show({ a: 1 })).toBe('{"a":1}');
  });
});
