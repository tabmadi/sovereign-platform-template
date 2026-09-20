// Kratos self-service registration flow, a public route under the landing shell (ADR-0304, ADR-0400).
import { getTranslations } from "next-intl/server";
import { KratosFlow } from "@/components/auth/KratosFlow";
import { Link } from "@/i18n/navigation";

export default async function RegisterPage() {
  const t = await getTranslations("auth.register");

  return (
    <KratosFlow
      kind="registration"
      strings={{
        title: t("title"),
        starting: t("starting"),
        submit: t("submit"),
        error: t("error"),
      }}
      footer={
        <Link href="/auth/login" className="mt-4 block text-sm text-primary hover:underline">
          {t("toLogin")}
        </Link>
      }
    />
  );
}
