// The locale set and the URL shape (ADR-0400).
//
// `as-needed` prefixing: the default locale is served unprefixed (`/panel`) and
// every other locale carries its tag (`/de/panel`, `/fa/panel`). One URL per
// language is what makes a page indexable per language; leaving the default
// unprefixed keeps the canonical English URLs, every e2e path, and the Lighthouse
// targets unchanged, which is the difference between adopting i18n and rewriting
// every address in the repository.
//
// The locale set is deliberately small and deliberately not all-LTR: `fa` is here
// from day one so that a mirrored layout is a case the design system passes on
// every commit rather than a project someone opens later. Removing it removes the
// only pressure keeping logical properties in the markup.
import { defineRouting } from "next-intl/routing";

/**
 * The cookie the chosen locale is remembered in. `NEXT_LOCALE` is the name
 * next-intl's own tooling expects, and it is declared here as a plain constant
 * because the proxy reads and writes it — `routing.localeCookie` is typed as the
 * library's cookie CONFIGURATION, not as a name.
 */
export const LOCALE_COOKIE = "NEXT_LOCALE";

export const routing = defineRouting({
  locales: ["en", "de", "fa"],
  defaultLocale: "en",
  localePrefix: "as-needed",
  localeCookie: { name: LOCALE_COOKIE },
});

export type Locale = (typeof routing.locales)[number];

/** Writing direction per locale, stamped onto <html dir>. */
export const localeDirection: Record<Locale, "ltr" | "rtl"> = {
  en: "ltr",
  de: "ltr",
  fa: "rtl",
};

/** Each locale's name IN that locale, which is how a language picker names it. */
export const localeLabel: Record<Locale, string> = {
  en: "English",
  de: "Deutsch",
  fa: "فارسی",
};

export function isLocale(value: string): value is Locale {
  return (routing.locales as readonly string[]).includes(value);
}
