"use client";

import { useTranslations } from "next-intl";
import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import { obsLog } from "@/lib/observability/log";

export default function RootError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const t = useTranslations("errors.unexpected");

  useEffect(() => {
    obsLog.error(error, { digest: error.digest });
  }, [error]);

  return (
    <main className="p-6">
      <h1 className="text-xl font-semibold text-foreground">{t("title")}</h1>
      {/* The message is the exception's own text, from the service or the runtime.
          It is not copy and is not translated: it is evidence, and it has to match
          what the logs and the error tracker hold (ADR-0503). */}
      <p className="mt-2 text-sm text-muted-foreground">{error.message}</p>
      <div className="mt-4">
        <Button onClick={reset}>{t("retry")}</Button>
      </div>
    </main>
  );
}
