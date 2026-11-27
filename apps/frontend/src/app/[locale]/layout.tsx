import "@/styles/globals.css";

import type { Metadata } from "next";
import localFont from "next/font/local";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations } from "next-intl/server";
import type { ReactNode } from "react";
import { type Locale, localeDirection, routing } from "@/i18n/routing";
import { ObservabilityInit } from "./observability-init";
import { Providers } from "./providers";

// The document title is copy, so it is translated and not hardcoded. A German page with an English tab title is only half localised.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("landing");
  return { title: t("title") };
}

// The document root is here because `lang` and `dir` depend on the locale, and only this segment knows the locale.
// Two fonts, one variable: Inter has no Persian coverage. So each font declares the same custom property, the locale selects which one loads, and `--font-sans` stays one token.
// The fonts come from packages in bun.lock, so a build fetches nothing, per the egress ADR of tabkit. A loader takes literals.
const inter = localFont({
  src: "../../../../../node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
  weight: "100 900",
  variable: "--font-app",
  display: "swap",
});
const vazirmatn = localFont({
  src: "../../../../../node_modules/@fontsource-variable/vazirmatn/files/vazirmatn-arabic-wght-normal.woff2",
  weight: "100 900",
  variable: "--font-app",
  display: "swap",
});

// Prerender every locale, and do not resolve them on demand.
export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  // The proxy rewrites only to a known locale. So this catches a request that reached the app another way,
  // such as a hand-typed `/xx/panel`, or a matcher that no longer covers this path.
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  // Makes this subtree use static rendering. Without it, every page under a locale becomes dynamic when it reads a message.

  const font = locale === "fa" ? vazirmatn : inter;

  return (
    <html
      lang={locale}
      dir={localeDirection[locale as Locale]}
      className={font.variable}
      suppressHydrationWarning
    >
      <body className="min-h-screen bg-background text-foreground antialiased">
        <NextIntlClientProvider>
          <Providers>
            <ObservabilityInit />
            {children}
          </Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
