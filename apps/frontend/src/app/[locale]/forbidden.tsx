// 403 fallback (ADR-0400). Rendered by `forbidden()` from lib/auth/denial.ts.
import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

export default function Forbidden() {
  const t = useTranslations("errors.forbidden");
  const common = useTranslations("common");

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="text-xl font-semibold text-foreground">{t("title")}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{t("body")}</p>
      <div className="mt-4 flex gap-4 text-sm">
        <Link href="/panel" className="text-primary hover:underline">
          {t("backToPanel")}
        </Link>
        <Link href="/" className="text-primary hover:underline">
          {common("home")}
        </Link>
      </div>
    </main>
  );
}
