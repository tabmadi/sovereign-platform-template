// The analytics seam (ADR-0400, ADR-0700, ADR-0701).
import { summary as fixtureSummary } from "@/fixtures/analytics";
import { createInternalClient } from "@/lib/server-fetch/internal";
import { fixturesEnabled } from "./mode";

export type EventSummary = { name: string; occurrences: number; sessions: number };

type AnalyticsPaths = {
  "/analytics/summary": {
    get: {
      parameters: { query: { since: string } };
      responses: { 200: { content: { "application/json": EventSummary[] } } };
    };
  };
};

export async function eventSummary(windowDays: number): Promise<EventSummary[]> {
  if (fixturesEnabled) {
    return fixtureSummary;
  }
  const analytics = createInternalClient<AnalyticsPaths>("ANALYTICS_URL");
  const since = new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000).toISOString();
  const { data } = await analytics.GET("/analytics/summary", { params: { query: { since } } });
  return data ?? [];
}
