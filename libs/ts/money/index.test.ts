import { describe, expect, test } from "bun:test";
import { formatMoney, InvalidMoneyError, parseMoney } from "./index";

const JSON_NUMBER_MESSAGE = /JSON number/;

describe("parseMoney", () => {
  test.each([
    ["a whole amount", "1299", "EUR"],
    ["two decimal places", "1299.00", "EUR"],
    ["the full internal scale", "0.0001", "EUR"],
    ["a negative amount", "-12.50", "USD"],
  ])("accepts %s", (_name, amount, currency) => {
    expect(parseMoney({ amount, currency })).toEqual({ amount, currency });
  });

  test.each([
    ["a JSON number", { amount: 12.1, currency: "EUR" }],
    ["a missing amount", { currency: "EUR" }],
    ["a thousands separator", { amount: "1,299.00", currency: "EUR" }],
    ["excess precision", { amount: "1.000005", currency: "EUR" }],
    ["a lowercase currency", { amount: "1.00", currency: "eur" }],
    ["a currency symbol", { amount: "1.00", currency: "€" }],
    ["a missing currency", { amount: "1.00" }],
    ["null", null],
  ])("rejects %s", (_name, value) => {
    expect(() => parseMoney(value)).toThrow(InvalidMoneyError);
  });

  // The string form exists to prevent this failure, so it gets its own message.
  // `expected a string` sends the reader to the wrong side of the wire.
  test("names the JSON-number failure", () => {
    expect(() => parseMoney({ amount: 12.1, currency: "EUR" })).toThrow(JSON_NUMBER_MESSAGE);
  });
});

describe("formatMoney", () => {
  // Fixed locales. The runtime's own locale is the CI container's setting, and an
  // assertion against it passes or fails by accident.
  test("renders the currency's symbol and separators for the reader's locale", () => {
    expect(formatMoney({ amount: "1299.00", currency: "EUR" }, "en-US")).toBe("€1,299.00");
    expect(formatMoney({ amount: "1299.00", currency: "USD" }, "en-US")).toBe("$1,299.00");
  });

  // This is an Intl call and not `/ 100` with `toFixed(2)`. The minor digits belong
  // to the currency, and two of these three currencies do not have two.
  test.each([
    ["JPY has no minor unit", "1000", "JPY", "¥1,000"],
    // \u00a0, not a space. Intl puts a non-breaking space between a currency CODE and
    // the number, so a plain space fails on a difference that nobody can see.
    ["KWD has three", "1.500", "KWD", "KWD\u00a01.500"],
    ["EUR has two", "1.50", "EUR", "€1.50"],
  ])("%s", (_name, amount, currency, want) => {
    expect(formatMoney({ amount, currency }, "en-US")).toBe(want);
  });

  // A unit price can be finer than the currency's minor unit. Rounding it for
  // display shows a price that nobody paid.
  test("keeps the precision the amount arrived with", () => {
    expect(formatMoney({ amount: "0.0125", currency: "EUR" }, "en-US")).toBe("€0.0125");
  });
});
