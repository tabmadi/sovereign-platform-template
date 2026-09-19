// Unmatched URLs, so the 404 is the localised one (ADR-0400).
//
// Without this, a path that matches no route falls out of the `[locale]` segment to
// Next's own built-in 404 — an English page with no styling, for every reader. The
// segment's `not-found.tsx` only renders for a `notFound()` thrown INSIDE it, which
// is what this catch-all turns an unmatched path into.
import { notFound } from "next/navigation";

export default function CatchAllNotFound() {
  notFound();
}
