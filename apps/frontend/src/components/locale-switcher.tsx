// The language picker (ADR-0400). A reader's explicit choice, which is why it
// writes the locale cookie the proxy then prefers over `Accept-Language`.
//
// `router.replace` with a locale rather than a hand-built href: the navigation
// helpers own the prefix rule, so the default locale drops its prefix and the others
// keep theirs without this component knowing which is which. It replaces rather than
// pushes, so switching language does not fill the back button with the same page in
// three languages.
"use client";

import { useParams } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useTransition } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { usePathname, useRouter } from "@/i18n/navigation";
import { type Locale, localeLabel, routing } from "@/i18n/routing";

export function LocaleSwitcher() {
  const t = useTranslations("common");
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams();
  const [isPending, startTransition] = useTransition();

  // A stable reference: the Select remounts its listener otherwise.
  const onChange = useCallback(
    (next: string) => {
      startTransition(() => {
        // `params` carries any dynamic segments of the current route, which
        // `router.replace` needs to rebuild the same page in the new locale.
        router.replace(
          // @ts-expect-error — typedRoutes cannot prove a runtime pathname is a known
          // route; it is the pathname this component was rendered on.
          { pathname, params },
          { locale: next as Locale },
        );
      });
    },
    [router, pathname, params],
  );

  return (
    <Select value={locale} onValueChange={onChange} disabled={isPending}>
      <SelectTrigger className="mt-6 w-44" aria-label={t("language")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {routing.locales.map((option) => (
          <SelectItem key={option} value={option}>
            {localeLabel[option]}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
