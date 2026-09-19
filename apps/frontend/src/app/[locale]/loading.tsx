// Root loading boundary (ADR-0400). Per-route-group versions override this.
//
// The copy is translated like every other surface, and this file receives no props
// to get a locale from — which is exactly why the locale is resolved from
// `next/root-params` in i18n/request.ts rather than threaded through layouts.
import { Loader2Icon } from "lucide-react";
import { useTranslations } from "next-intl";

export default function Loading() {
  const t = useTranslations("errors");

  return (
    <main className="p-6" aria-busy="true">
      <Loader2Icon className="size-5 animate-spin text-muted-foreground" aria-hidden="true" />
      <span className="sr-only">{t("loading")}</span>
    </main>
  );
}
