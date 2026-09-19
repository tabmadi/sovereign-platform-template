/**
 * Fixture mode: the one switch that makes design mode possible (ADR-0701).
 *
 * A screen is designed at its final URL, in the real shell, on the real tokens,
 * before the API that feeds it exists. What differs between a screen under design
 * and a finished one is where its data comes from — nothing else — so that
 * difference is one boolean read by `lib/data/*` and by nothing else.
 *
 * `NEXT_PUBLIC_` because both halves of the seam read it: a server component
 * resolving a fixture and a client mutation stubbing a response are the same
 * decision, and a variable only the server could see would split it in two.
 *
 * The guard below is the whole production story. Fixtures are committed source that
 * looks exactly like real data, which is what makes them useful and what makes
 * shipping them a silent failure rather than a loud one — a page that renders
 * plausible numbers nobody ordered. Next inlines this value at build time, so a
 * production build with the switch set fails here, during prerender, rather than
 * serving invented data. Nothing has to remember a flag.
 */
const enabled = process.env.NEXT_PUBLIC_FIXTURES === "1";

if (enabled && process.env.NODE_ENV === "production") {
  throw new Error(
    "NEXT_PUBLIC_FIXTURES is a design-time switch and must be unset in a production build (ADR-0701)",
  );
}

export const fixturesEnabled = enabled;
