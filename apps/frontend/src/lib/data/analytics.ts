// The analytics seam, per ADR-0400, ADR-0700, and ADR-0701.
import type { components, paths } from "@sdks/analytics";
import { summary as fixtureSummary } from "@/fixtures/analytics";
import { createInternalClient } from "@/lib/server-fetch/internal";
import { fixturesEnabled } from "./mode";

export type EventSummary = components["schemas"]["EventSummary"];

export async function eventSummary(windowDays: number): Promise<EventSummary[]> {
  if (fixturesEnabled) {
    return fixtureSummary;
  }
  const analytics = createInternalClient<paths>("ANALYTICS_URL");
  const since = new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000).toISOString();
  const { data } = await analytics.GET("/analytics/summary", { params: { query: { since } } });
  return data ?? [];
}
