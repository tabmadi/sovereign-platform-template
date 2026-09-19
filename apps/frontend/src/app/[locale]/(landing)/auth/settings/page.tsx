// Kratos self-service settings flow (ADR-0304, ADR-0400). Requires a session —
// Kratos redirects the browser flow to login when unauthenticated. The shared
// KratosFlow component renders the flow.
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
