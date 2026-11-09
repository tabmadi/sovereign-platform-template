import { notFound } from "next/navigation";

/**
 * Fixture mode: the one switch that makes design mode possible, per ADR-0701. A screen under design differs from a finished one only in its data source.
 * It is `NEXT_PUBLIC_` because both halves read it, and Next inlines it, so the guard below fails a production build. The design build also sets `NEXT_PUBLIC_DESIGN_BUILD`.
 */
export function resolveFixtureMode(
  fixtures?: string,
  designBuild?: string,
  nodeEnv?: string,
): boolean {
  const enabled = fixtures === "1";
  if (enabled && nodeEnv === "production" && designBuild !== "1") {
    throw new Error(
      "NEXT_PUBLIC_FIXTURES is a design-time switch and must be unset in a production build, unless NEXT_PUBLIC_DESIGN_BUILD=1 marks the design build (ADR-0701)",
    );
  }
  return enabled;
}

// Each variable is read by its literal name, because Next inlines only a literal `process.env.NEXT_PUBLIC_*` into the browser bundle.
export const fixturesEnabled = resolveFixtureMode(
  process.env.NEXT_PUBLIC_FIXTURES,
  process.env.NEXT_PUBLIC_DESIGN_BUILD,
  process.env.NODE_ENV,
);

/**
 * A page whose endpoint no spec has yet is design-only, per ADR-0701. Its seam calls this before the real call, so
 * outside fixture mode the page answers 404 and never calls a missing endpoint. `lint:fixtures` requires the call.
 */
export function designOnly(enabled: boolean = fixturesEnabled): void {
  if (!enabled) {
    notFound();
  }
}
