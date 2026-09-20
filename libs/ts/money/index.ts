/**
 * Monetary amounts on the TypeScript side (ADR-0300, ADR-0100), and deliberately much smaller than libs/go/money.
 * The amount stays a string throughout: `JSON.parse` turns a JSON number into an IEEE-754 double, and 12.10 is not one.
 * There is no arithmetic here — a client computing a total is computing one the server will compute again.
 */

/** The wire form of a monetary amount: the shared `Money` component of every spec. */
export type Money = {
  /** Decimal, sign-prefixed when negative, no thousands separators. */
  readonly amount: string;
  /** ISO 4217 alphabetic code, uppercase. */
  readonly currency: string;
};

/** Thrown by {@link parseMoney}. Named so a caller can tell it from a network error. */
export class InvalidMoneyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidMoneyError";
  }
}

const AMOUNT_PATTERN = /^-?[0-9]+(\.[0-9]+)?$/;

const CURRENCY_PATTERN = /^[A-Z]{3}$/;

/**
 * The internal scale of `libs/go/money`, and the most decimal places an amount can
 * arrive with. It is finer than any currency's minor unit because a unit price can
 * be, and rejecting the excess is better than silently truncating it.
 */
const MAX_FRACTION_DIGITS = 4;

/**
 * parseMoney validates an untrusted value and returns it as {@link Money}. Use it at the edge, not on a value
 * this module returned. It catches contract drift — a field that became a number, a null where the spec said
 * required — which otherwise reaches a component as `undefined` and renders as "NaN".
 */
export function parseMoney(value: unknown): Money {
  if (typeof value !== "object" || value === null) {
    throw new InvalidMoneyError(`money: expected an object, got ${typeof value}`);
  }
  const { amount, currency } = value as Record<string, unknown>;

  // A number here is the specific failure the string form exists to prevent, so it
  // gets its own message rather than "expected a string".
  if (typeof amount === "number") {
    throw new InvalidMoneyError(
      "money: amount is a JSON number, which cannot hold a decimal exactly",
    );
  }
  if (typeof amount !== "string" || !AMOUNT_PATTERN.test(amount)) {
    throw new InvalidMoneyError(`money: not a decimal amount: ${JSON.stringify(amount)}`);
  }
  const fraction = amount.split(".")[1] ?? "";
  if (fraction.length > MAX_FRACTION_DIGITS) {
    throw new InvalidMoneyError(
      `money: more than ${MAX_FRACTION_DIGITS} decimal places in ${amount}`,
    );
  }
  if (typeof currency !== "string" || !CURRENCY_PATTERN.test(currency)) {
    throw new InvalidMoneyError(
      `money: currency must be three uppercase letters: ${JSON.stringify(currency)}`,
    );
  }
  return { amount, currency };
}

/**
 * formatMoney renders an amount for a human. The locale defaults to `Intl`'s runtime locale, which in a Server
 * Component is the server's and not the reader's — pass the negotiated one where it matters.
 * `Intl.NumberFormat` takes the minor digits from the currency: hardcoding two renders ¥1000 as ¥10.00.
 */
export function formatMoney(value: Money, locale?: string): string {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: value.currency,
    // A unit price can carry four decimal places while the currency has two, so the maximum floats up to the amount's own precision.
    maximumFractionDigits: Math.max(
      fractionDigits(value.amount),
      currencyDigits(value.currency, locale),
    ),
  }).format(Number(value.amount));
}

/** The decimal places actually present in the amount. */
function fractionDigits(amount: string): number {
  return (amount.split(".")[1] ?? "").length;
}

/** The currency's own minor-unit digits, as the runtime's CLDR data has them. */
function currencyDigits(currency: string, locale?: string): number {
  return (
    new Intl.NumberFormat(locale, { style: "currency", currency }).resolvedOptions()
      .maximumFractionDigits ?? 2
  );
}
