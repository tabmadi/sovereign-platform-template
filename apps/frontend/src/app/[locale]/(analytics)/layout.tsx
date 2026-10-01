// Analytics route-group layout, per ADR-0700.
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { requireRelation } from "@/lib/auth/panel-access";

// `noindex`, because the pages are on the PRODUCT origin, which crawlers are invited to.
// The authorization check below protects them. This only keeps them out of search results.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

// Every render asks. A cached answer would cache an authorization decision, which must reflect the request being served.
// A grant withdrawn a minute ago must take effect on the next page load.
export const dynamic = "force-dynamic";

export default async function AnalyticsLayout({ children }: { children: ReactNode }) {
  await requireRelation("view", "analytics_panel:funnels");
  return <section className="mx-auto max-w-4xl p-6">{children}</section>;
}
