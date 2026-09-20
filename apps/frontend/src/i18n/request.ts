// The per-request locale and its messages (ADR-0400).

import { locale as localeParam } from "next/root-params";
import { hasLocale } from "next-intl";
import { getRequestConfig } from "next-intl/server";
import { routing } from "./routing";

export default getRequestConfig(async () => {
  // Read from the root params rather than threaded through every layout: `setRequestLocale` is deprecated, and the request shells that render first have no props to thread.
  const requested = await localeParam();
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../messages/${locale}.json`)).default,
    // Both are required for static rendering: left unset, one request-time read in a layout opts the whole
    // `[locale]` subtree into dynamic rendering.
    // UTC because a server's local zone is not a product decision.
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
