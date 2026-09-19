import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";

export default async function PanelHome() {
  const t = await getTranslations("panel.home");
  return (
    <main className="mx-auto max-w-3xl p-6">
      <h1 className="text-2xl font-semibold">{t("title")}</h1>
      <ul className="mt-4 space-y-2">
        <li>
          <Link href="/panel/products" className="text-primary hover:underline">
            {t("products")}
          </Link>
        </li>
        <li>
          <Link href="/panel/checkout" className="text-primary hover:underline">
            {t("checkout")}
          </Link>
        </li>
      </ul>
    </main>
  );
}
