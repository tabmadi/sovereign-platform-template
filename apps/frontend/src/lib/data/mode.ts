/**
 * Fixture mode: the one switch that makes design mode possible (ADR-0701). What differs between a screen under
 * design and a finished one is where its data comes from, so that difference is one boolean read by `lib/data/*`.
 * `NEXT_PUBLIC_` because both halves read it, and Next inlines it, so the guard below fails a production build.
 */
const enabled = process.env.NEXT_PUBLIC_FIXTURES === "1";

if (enabled && process.env.NODE_ENV === "production") {
  throw new Error(
    "NEXT_PUBLIC_FIXTURES is a design-time switch and must be unset in a production build (ADR-0701)",
  );
}

export const fixturesEnabled = enabled;
