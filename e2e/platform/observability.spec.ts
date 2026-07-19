// Observability gauge (ADR-0011), two layers:
//
//  1. Datasource health — the three Grafana datasources resolve and answer. This is
//     the wiring check behind the service-name fix: Grafana, the OTel collector and
//     prod all reach Loki/Tempo/Prometheus at their short in-cluster names, and Loki
//     runs single-tenant so header-less queries don't 401. Driven through the real
//     ops edge with the saved AAL2 operator session (Grafana's HTTP API, no browser).
//
//  2. End-to-end signal correlation — one real checkout, then assert all three
//     signals landed and cross-reference each other: a single trace stitched across
//     orders+catalog+payment (Tempo), log lines carrying that trace_id from every
//     service (Loki), and the RED/domain counters moved (Prometheus). This is the
//     regression gauge for the propagation + log-export + netpol fixes — with any of
//     them broken the trace fragments, the logs lose their trace_id, or the checkout
//     never reaches payment.
import { type APIRequestContext, expect, request, test } from "@playwright/test";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { portForward } from "../fixtures/kube";
import {
  forwardObservability,
  lokiServicesForTrace,
  newTraceparent,
  type ObsForwards,
  promSeriesCount,
  waitForTraceServices,
} from "../fixtures/observability";

const GRAFANA_API = `${opsURL("o11y")}/api/datasources`;

test.describe("grafana datasources", () => {
  for (const name of ["Loki", "Tempo", "Prometheus"]) {
    test(`${name} datasource is healthy behind the operator session`, async () => {
      const ctx: APIRequestContext = await request.newContext({
        ignoreHTTPSErrors: true,
        storageState: OPERATOR_STATE,
      });
      try {
        const ds = await ctx.get(`${GRAFANA_API}/name/${name}`);
        expect(ds.ok(), `${name} datasource is provisioned`).toBeTruthy();
        const { uid } = await ds.json();
        const health = await ctx.get(`${GRAFANA_API}/uid/${uid}/health`);
        expect(health.ok(), `${name} health endpoint reachable`).toBeTruthy();
        expect((await health.json()).status, `${name} reachable from Grafana`).toBe("OK");
      } finally {
        await ctx.dispose();
      }
    });
  }
});

// A checkout drives every signal at once. Rather than the browser, this layer hits
// the services east-west through port-forwards with a KNOWN inbound traceparent, so
// the trace id is fixed up front (no search race) and the assertions are
// deterministic. The browser-driven equivalent lives in purchase.spec.ts.
test.describe("end-to-end signal correlation", () => {
  const CATALOG_PORT = 18081;
  const ORDERS_PORT = 18082;
  let stopCatalog: () => void;
  let stopOrders: () => void;
  let obs: ObsForwards;

  test.beforeAll(async () => {
    ({ stop: stopCatalog } = await portForward("catalog-server", CATALOG_PORT, 80));
    ({ stop: stopOrders } = await portForward("orders-server", ORDERS_PORT, 80));
    obs = await forwardObservability();
  });

  test.afterAll(() => {
    stopCatalog?.();
    stopOrders?.();
    obs?.stop();
  });

  test("a checkout emits a stitched trace, correlated logs and metrics @smoke", async () => {
    test.setTimeout(180_000);
    const catalog = `http://127.0.0.1:${CATALOG_PORT}`;
    const orders = `http://127.0.0.1:${ORDERS_PORT}`;

    // Operator-authored product (X-User-Id admin-console holds group:operator, the
    // same subject the admin console writes as — ADR-0012).
    const productRes = await fetch(`${catalog}/products`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-user-id": "admin-console" },
      body: JSON.stringify({ name: `obs-e2e-${Date.now()}`, price_cents: 4200 }),
    });
    expect(productRes.ok, "operator can create a product").toBeTruthy();
    const productId = ((await productRes.json()) as { id: string }).id;

    // Checkout with a known, sampled traceparent → the trace id is fixed.
    const { header, traceId } = newTraceparent();
    const orderRes = await fetch(`${orders}/orders`, {
      method: "POST",
      headers: { "content-type": "application/json", traceparent: header },
      body: JSON.stringify({ product_id: productId, quantity: 2 }),
    });
    expect(orderRes.status, "checkout accepted (202)").toBe(202);
    const orderId = ((await orderRes.json()) as { run_id: string }).run_id;

    // The saga is async: poll the order until it confirms (catalog lookup + payment
    // charge both succeeded — the reachability the netpol fix restored).
    await expect
      .poll(
        async () => {
          const r = await fetch(`${orders}/orders/${orderId}`);
          return ((await r.json()) as { status: string }).status;
        },
        { timeout: 90_000, intervals: [1000, 2000, 3000] },
      )
      .toBe("confirmed");

    // TEMPO: one trace, three services. The cross-service stitch — broken before the
    // global propagator + otelhttp-transport fixes.
    const services = await waitForTraceServices(traceId, ["orders", "catalog", "payment"]);
    expect(services).toEqual(expect.arrayContaining(["orders", "catalog", "payment"]));

    // LOKI: the same trace_id appears in log structured metadata for each service —
    // logs↔traces correlation, broken before the access-log-inside-span reorder and
    // the gRPC log-export fix.
    let logServices: string[] = [];
    await expect
      .poll(
        async () => {
          logServices = await lokiServicesForTrace(traceId);
          return ["orders", "catalog", "payment"].every((s) => logServices.includes(s));
        },
        { timeout: 60_000, intervals: [2000, 3000, 5000] },
      )
      .toBe(true);
    expect(logServices).toEqual(expect.arrayContaining(["orders", "catalog", "payment"]));

    // PROMETHEUS: the domain + RED counters moved. Prometheus escapes OTLP dotted
    // names to the classic underscore form (UnderscoreEscapingWithSuffixes), so the
    // stored series are orders_checkouts_started_total / http_server_requests_total.
    await expect
      .poll(async () => await promSeriesCount("orders_checkouts_started_total"), { timeout: 60_000 })
      .toBeGreaterThan(0);
    expect(await promSeriesCount("http_server_requests_total")).toBeGreaterThan(0);
    expect(await promSeriesCount("catalog_products_created_total")).toBeGreaterThan(0);
  });
});
