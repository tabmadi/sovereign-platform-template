// The locale and messages for each request, per ADR-0400.

import { locale as localeParam } from "next/root-params";
import { hasLocale } from "next-intl";
import { getRequestConfig } from "next-intl/server";
import { routing } from "./routing";

export default getRequestConfig(async () => {
  // Read from the root params and not passed through every layout: `setRequestLocale` is deprecated, and the request shells that render first have no props.
  const requested = await localeParam();
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../messages/${locale}.json`)).default,
    // Both are required for static rendering. If they are unset, one request-time read in a layout makes the whole `[locale]` subtree dynamic.
    // UTC, because a server's local zone is not a product decision.
    timeZone: "UTC",
    // A missing or malformed message is a bug, and a translator's typo causes it with no signal.
    // In development it throws. In production it renders the key path, so copy never crashes a page.
    onError(error) {
      if (process.env.NODE_ENV !== "production") {
        throw error;
      }
    },
  };
});
