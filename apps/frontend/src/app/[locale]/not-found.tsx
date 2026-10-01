import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

export default function NotFound() {
  const t = useTranslations("errors.notFound");

  return (
    <main className="p-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      {/* `t.rich`, not two keys. A sentence split into two keys cannot be reordered by a
      translator, and word order is what changes between languages. */}
      <p className="mt-2 text-sm text-muted-foreground">
        {t.rich("body", {
          home: (chunks) => (
            <Link href="/" className="text-primary hover:underline">
              {chunks}
            </Link>
          ),
        })}
      </p>
    </main>
  );
}
