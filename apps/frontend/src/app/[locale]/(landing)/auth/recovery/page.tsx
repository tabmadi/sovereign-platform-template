// Kratos self-service recovery flow, a public route under the landing shell (ADR-0304, ADR-0400).
import { getTranslations } from "next-intl/server";
import { KratosFlow } from "@/components/auth/KratosFlow";
import { Link } from "@/i18n/navigation";

export default async function RecoveryPage() {
  const t = await getTranslations("auth.recovery");

  return (
    <KratosFlow
      kind="recovery"
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
