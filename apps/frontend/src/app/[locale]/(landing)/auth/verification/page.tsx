// Kratos self-service verification flow (ADR-0304, ADR-0400). Public route under
// (landing); confirms ownership of the email via a code (delivery needs a wired
// SMTP sink). The shared KratosFlow component renders the flow.
import { getTranslations } from "next-intl/server";
import { KratosFlow } from "@/components/auth/KratosFlow";
import { Link } from "@/i18n/navigation";

export default async function VerificationPage() {
  const t = await getTranslations("auth.verification");

  return (
    <KratosFlow
      kind="verification"
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
