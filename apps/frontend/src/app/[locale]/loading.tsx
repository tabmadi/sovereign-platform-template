// Root loading boundary (ADR-0400). Per-route-group versions override this.
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
