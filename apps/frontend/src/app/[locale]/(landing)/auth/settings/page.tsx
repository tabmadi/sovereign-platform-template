// Kratos self-service settings flow (ADR-0304, ADR-0400); Kratos redirects to login without a session.
import { getTranslations } from "next-intl/server";
import { KratosFlow } from "@/components/auth/KratosFlow";

export default async function SettingsPage() {
  const t = await getTranslations("auth.settings");

  return (
    <KratosFlow
      kind="settings"
      strings={{
        title: t("title"),
        starting: t("starting"),
        submit: t("submit"),
        error: t("error"),
      }}
    />
  );
}
