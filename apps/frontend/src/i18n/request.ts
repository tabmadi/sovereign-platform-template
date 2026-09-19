// The per-request locale and its messages (ADR-0400).
//
// The locale comes from the `[locale]` route segment, which the proxy has already
// resolved and rewritten — next-intl's own middleware is NOT used, because the
// proxy must resolve the locale before it can build a locale-correct auth redirect,
// and two middlewares cannot both own the rewrite. See the note in proxy.ts.
//
// Messages are loaded per request and per locale, so a locale nobody visits costs
// nothing in the bundle.

import { locale as localeParam } from "next/root-params";
import { hasLocale } from "next-intl";
import { getRequestConfig } from "next-intl/server";
import { routing } from "./routing";

export default getRequestConfig(async () => {
  // The `[locale]` segment, read straight from the root params rather than threaded
  // through every layout and page. `setRequestLocale` is next-intl's older answer and
  // is deprecated in favour of this; it also could not work here, because the request
  // shells that render first have no props to thread.
  const requested = await localeParam();
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../messages/${locale}.json`)).default,
    // Both of these are REQUIRED for static rendering, and neither is obvious.
    // Left unset, next-intl resolves the time zone and "now" from the request, and
    // one request-time read in a layout opts the whole `[locale]` subtree into
    // dynamic rendering — the landing page silently stops being prerendered.
    //
    // UTC because a server's local zone is not a product decision: a timestamp
    // rendered for a reader belongs in that reader's zone, which is a preference the
    // product has to carry, not an accident of which node rendered the page.
    timeZone: "UTC",
    // A missing or malformed message is a bug, and one that a translator's typo
    // produces silently. In development it throws; in production it renders the
    // key path rather than crashing a page over copy.
    onError(error) {
      if (process.env.NODE_ENV !== "production") {
        throw error;
      }
    },
  };
});
