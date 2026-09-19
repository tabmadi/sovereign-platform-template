import "@/styles/globals.css";

import type { Metadata } from "next";
import { Inter, Vazirmatn } from "next/font/google";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations } from "next-intl/server";
import type { ReactNode } from "react";
import { type Locale, localeDirection, routing } from "@/i18n/routing";
import { ObservabilityInit } from "./observability-init";
import { Providers } from "./providers";

// The document title is copy, so it is translated rather than hardcoded — a German
// page with an English tab title is half localised.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("landing");
  return { title: t("title") };
}

// The document root lives here rather than in a root layout, because `lang` and
// `dir` are per-locale and only this segment knows the locale. Every route is under
// `[locale]`; `app/api/*` are route handlers and need no layout.
//
// Two fonts, one variable. Inter has no Persian coverage, so a fa reader on Inter
// gets the browser's fallback for every glyph — the layout is translated and the
// typography is not. Each font declares the SAME custom property and the locale
// picks which one is loaded, so `--font-sans` in theme.css stays a single token.
const inter = Inter({ subsets: ["latin"], variable: "--font-app", display: "swap" });
const vazirmatn = Vazirmatn({ subsets: ["arabic"], variable: "--font-app", display: "swap" });

// Prerender every locale rather than resolving them on demand.
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
  // The proxy only ever rewrites to a known locale, so this catches a request that
  // reached the app another way — a hand-typed `/xx/panel`, or a matcher that stops
  // covering this path.
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  // Opts this subtree into static rendering: without it every page under a locale
  // becomes dynamic the moment it reads a message.

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
