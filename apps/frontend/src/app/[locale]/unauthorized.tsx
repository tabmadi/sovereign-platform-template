// 401 fallback, per ADR-0400. `unauthorized()` from lib/auth/denial.ts renders it.
import { useTranslations } from "next-intl";
import { SignInAgain } from "./sign-in-again";

export default function Unauthorized() {
  const t = useTranslations("errors.unauthorized");

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="text-xl font-semibold text-foreground">{t("title")}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{t("body")}</p>
      <div className="mt-4">
        <SignInAgain />
      </div>
    </main>
  );
}
