// Kratos self-service registration flow (ADR-0304, ADR-0400). Public route under
// (landing). No seeded users exist — this is how the first identity is created.
// The shared KratosFlow component renders the flow.
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
