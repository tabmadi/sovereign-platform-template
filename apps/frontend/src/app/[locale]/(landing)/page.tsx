import { getTranslations } from "next-intl/server";
import { LocaleSwitcher } from "@/components/locale-switcher";
import { Link } from "@/i18n/navigation";

export default async function Landing() {
  const t = await getTranslations("landing");

  // The routes are data, so the list is one map rather than six copies of a <li>.
  const entries = [
    { href: "/auth/login", label: t("signIn") },
    { href: "/auth/register", label: t("createAccount") },
    { href: "/auth/recovery", label: t("forgotPassword") },
    { href: "/auth/settings", label: t("accountSettings") },
    { href: "/panel", label: t("customerPanel") },
    { href: "/devportal", label: t("developerPortal") },
  ] as const;

  return (
    <main className="mx-auto max-w-3xl p-6">
      <h1 className="text-3xl font-semibold">{t("title")}</h1>
      <p className="mt-2 text-muted-foreground">{t("tagline")}</p>
      <ul className="mt-6 space-y-2">
        {entries.map((entry) => (
          <li key={entry.href}>
            <Link href={entry.href} className="text-primary hover:underline">
              {entry.label}
            </Link>
          </li>
        ))}
      </ul>
      <LocaleSwitcher />
    </main>
  );
}
