// Analytics route-group layout (ADR-0700).
import type { Metadata } from "next";
import type { ReactNode } from "react";
import { requireRelation } from "@/lib/auth/panel-access";

// `noindex` because the pages sit on the PRODUCT origin, which is the origin
// crawlers are invited to. The authorization check below is what actually
// protects them — this only keeps them out of results.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

// Every render asks. Caching the answer would cache an authorization decision,
// which is the one thing that must reflect the request being served: a grant
// withdrawn a minute ago has to take effect on the next page load.
export const dynamic = "force-dynamic";

export default async function AnalyticsLayout({ children }: { children: ReactNode }) {
  await requireRelation("view", "analytics_panel:funnels");
  return <section className="mx-auto max-w-4xl p-6">{children}</section>;
}
