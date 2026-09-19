// 401 fallback (ADR-0400). Rendered by `unauthorized()` from lib/auth/denial.ts.
//
// Reached when a session runs out DURING a page — the proxy already turns a
// session-less navigation into a 307 before anything renders, so this is the case
// the proxy cannot catch. That difference is why this is a page and not a redirect:
// at navigation time nothing is lost by redirecting, but here the user may be
// mid-form, and bouncing the document would discard what they typed. Signing in is
// offered as a link they choose to follow.
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
