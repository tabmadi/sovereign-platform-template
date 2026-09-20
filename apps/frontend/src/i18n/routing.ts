// The locale set and the URL shape (ADR-0400).
import { defineRouting } from "next-intl/routing";

/**
 * The cookie the chosen locale is remembered in. A plain constant because the proxy reads and writes it —
 * `routing.localeCookie` is typed as the library's cookie configuration, not as a name.
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
