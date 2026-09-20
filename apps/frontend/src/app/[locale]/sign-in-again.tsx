// The sign-in link on the 401 fallback (ADR-0400): a client component for one interaction.
"use client";

import type { Route } from "next";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

export function SignInAgain() {
  const t = useTranslations("errors.unauthorized");
  // Read after mount, not during render: the server pass has no location, and
  // deriving the href from it would mismatch on hydration.
  const [href, setHref] = useState("/auth/login");

  useEffect(() => {
    const returnTo = `${window.location.pathname}${window.location.search}`;
    setHref(`/auth/login?return_to=${encodeURIComponent(returnTo)}`);
  }, []);

  return (
    // typedRoutes cannot check a template string; the shape is asserted above.
    <Link href={href as Route} className="text-sm text-primary hover:underline">
      {t("signInAgain")}
    </Link>
  );
}
