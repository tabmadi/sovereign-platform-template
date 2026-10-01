// Query helpers for the end-to-end signal-correlation gauge, per ADR-0500.
import { expect } from "@playwright/test";
import { type PortForward, portForward } from "./kube";

export const TEMPO_PORT = 13200;
export const LOKI_PORT = 13100;
export const PROM_PORT = 19090;

// A minimal port-forward set for the observability stores. Callers open it once in beforeAll and call stop() in afterAll.
export type ObsForwards = { stop: () => void };

export async function forwardObservability(): Promise<ObsForwards> {
  const pfs: PortForward[] = [
    await portForward("tempo", TEMPO_PORT, 3200),
    await portForward("loki", LOKI_PORT, 3100),
    await portForward("prometheus", PROM_PORT, 9090),
  ];
  return { stop: () => pfs.forEach((p) => p.stop()) };
}

// The cross-service stitch assertion: a checkout trace must carry spans from orders, catalog, and payment under one id. It is empty if the trace is not queryable yet.
export async function tempoTraceServices(traceId: string): Promise<string[]> {
  const res = await fetch(`http://127.0.0.1:${TEMPO_PORT}/api/traces/${traceId}`);
  if (!res.ok) {
    return [];
  }
  const body = (await res.json()) as {
    batches?: { resource?: { attributes?: { key: string; value?: { stringValue?: string } }[] } }[];
  };
  const svcs = new Set<string>();
  for (const b of body.batches ?? []) {
    for (const a of b.resource?.attributes ?? []) {
      if (a.key === "service.name" && a.value?.stringValue) {
        svcs.add(a.value.stringValue);
      }
    }
  }
  return [...svcs];
}

// tempoSearchByOrderId finds the trace id for a checkout through the order.id span attribute that the orders handler sets.
// The query is TraceQL `{ .order.id = "<id>" }`. It returns the first matching trace id, or an empty string if no trace is queryable yet.
export async function tempoSearchByOrderId(orderId: string): Promise<string> {
  const q = encodeURIComponent(`{ .order.id = "${orderId}" }`);
  const now = Math.floor(Date.now() / 1000);
  const res = await fetch(
    `http://127.0.0.1:${TEMPO_PORT}/api/search?q=${q}&limit=5&start=${now - 3600}&end=${now}`,
  );
  if (!res.ok) {
    return "";
  }
  const body = (await res.json()) as { traces?: { traceID: string }[] };
  return body.traces?.[0]?.traceID ?? "";
}

// lokiServicesForTrace queries Loki for log lines that carry a given trace_id in structured metadata, with LogQL `| trace_id="<id>"`.
// It returns the distinct service_name labels that logged under it. This proves that logs and traces correlate.
export async function lokiServicesForTrace(traceId: string, windowSec = 900): Promise<string[]> {
  const now = Math.floor(Date.now() / 1000);
  const q = encodeURIComponent(`{service_namespace="platform"} | trace_id="${traceId}"`);
  const res = await fetch(
    `http://127.0.0.1:${LOKI_PORT}/loki/api/v1/query_range?query=${q}` +
      `&start=${(now - windowSec) * 1_000_000_000}&end=${now * 1_000_000_000}&limit=200`,
  );
  if (!res.ok) {
    return [];
  }
  const body = (await res.json()) as {
    data?: { result?: { stream?: Record<string, string> }[] };
  };
  const svcs = new Set<string>();
  for (const s of body.data?.result ?? []) {
    const name = s.stream?.service_name;
    if (name) {
      svcs.add(name);
    }
  }
  return [...svcs];
}

// Prometheus escapes OTLP names to the classic underscore form, so callers pass a name such as `orders_checkouts_started_total`.
export async function promSeriesCount(metric: string): Promise<number> {
  const q = encodeURIComponent(`{"${metric}"}`);
  const res = await fetch(`http://127.0.0.1:${PROM_PORT}/api/v1/query?query=${q}`);
  if (!res.ok) {
    return 0;
  }
  const body = (await res.json()) as { data?: { result?: unknown[] } };
  return body.data?.result?.length ?? 0;
}

// A W3C traceparent with the sampled flag set. The whole trace is kept, and the caller knows the trace id before the call, with no search.
// It returns { header, traceId }.
export function newTraceparent(): { header: string; traceId: string } {
  const hex = (n: number) =>
    [...crypto.getRandomValues(new Uint8Array(n))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const traceId = hex(16);
  return { header: `00-${traceId}-${hex(8)}-01`, traceId };
}

// waitForTraceServices polls until the given trace has spans from all `expected` services, then returns the observed set.
// It fails the test on timeout.
export async function waitForTraceServices(traceId: string, expected: string[]): Promise<string[]> {
  let seen: string[] = [];
  await expect
    .poll(async () => {
      seen = await tempoTraceServices(traceId);
      return expected.every((s) => seen.includes(s));
    }, { timeout: 60_000, intervals: [1000, 2000, 3000] })
    .toBe(true);
  return seen;
}
