import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

export default function NotFound() {
  const t = useTranslations("errors.notFound");

  return (
    <main className="p-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      {/* `t.rich`, not two keys: a sentence broken into "That page does not exist."
          plus "Go home" is a sentence no translator can reorder, and word order is
          exactly what changes between languages. */}
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
