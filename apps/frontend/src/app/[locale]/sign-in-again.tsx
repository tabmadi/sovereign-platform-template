// The sign-in link on the 401 fallback, per ADR-0400. It is a client component for one interaction.
"use client";

import type { Route } from "next";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

export function SignInAgain() {
  const t = useTranslations("errors.unauthorized");
  // Read after mount, not during render: the server pass has no location, and an href from it would not match on hydration.
  const [href, setHref] = useState("/auth/login");

  useEffect(() => {
    const returnTo = `${window.location.pathname}${window.location.search}`;
    setHref(`/auth/login?return_to=${encodeURIComponent(returnTo)}`);
  }, []);

  return (
    // typedRoutes cannot check a template string. The code above asserts the shape.
    <Link href={href as Route} className="text-sm text-primary hover:underline">
      {t("signInAgain")}
    </Link>
  );
}
