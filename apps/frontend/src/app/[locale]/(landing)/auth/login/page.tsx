// Kratos self-service login flow, a public route under the landing shell, per ADR-0304 and ADR-0400.
import { getTranslations } from "next-intl/server";
import { KratosFlow } from "@/components/auth/KratosFlow";
import { Link } from "@/i18n/navigation";

export default async function LoginPage() {
  const t = await getTranslations("auth.login");

  return (
    <KratosFlow
      kind="login"
      strings={{
        title: t("title"),
        starting: t("starting"),
        submit: t("submit"),
        error: t("error"),
      }}
      footer={
        <Link href="/auth/register" className="mt-4 block text-sm text-primary hover:underline">
          {t("toRegister")}
        </Link>
      }
    />
  );
}
