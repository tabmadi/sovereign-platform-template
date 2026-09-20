// Observability gauge (ADR-0500), two layers:
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

const GRAFANA_API = `${opsURL("grafana")}/api/datasources`;

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

// Network-policy denials (ADR-0500, ADR-0501). A missing `hubble-drops` dashboard means Grafana's provider is
// misconfigured — mounting JSON is not enough without a matching dashboardProviders entry.
// No hubble_drop_total series means the ingest path broke: Hubble metrics off, or the scrape not reaching :9965.
test.describe("network policy denials", () => {
  let ctx: APIRequestContext;

  test.beforeAll(async () => {
    ctx = await request.newContext({ ignoreHTTPSErrors: true, storageState: OPERATOR_STATE });
  });
  test.afterAll(async () => {
    await ctx?.dispose();
  });

  test("the drops dashboard is provisioned, not just mounted", async () => {
    const res = await ctx.get(`${opsURL("grafana")}/api/search?type=dash-db`);
    expect(res.ok(), "Grafana search API answers").toBeTruthy();
    const uids = ((await res.json()) as { uid: string }[]).map((d) => d.uid);
    expect(uids, "committed dashboards are registered with Grafana").toEqual(
      expect.arrayContaining(["hubble-drops"]),
    );
  });

  test("Hubble drop metrics reach Prometheus with workload labels", async () => {
    const ds = await ctx.get(`${opsURL("grafana")}/api/datasources/name/Prometheus`);
    expect(ds.ok(), "Prometheus datasource is provisioned").toBeTruthy();
    const { uid } = await ds.json();

    const res = await ctx.post(`${opsURL("grafana")}/api/ds/query`, {
      data: {
        from: "now-15m",
        to: "now",
        queries: [
          {
            refId: "A",
            datasource: { type: "prometheus", uid },
            // `sourceContext=workload` renders a combined "<namespace>/<workload>"
            // label, so grouping by it proves the workload context is on.
            expr: "sum by (source, destination) (rate(hubble_drop_total[5m]))",
            instant: true,
          },
        ],
      },
    });
    expect(res.ok(), "Grafana executes the drops query").toBeTruthy();
    const frames = (await res.json()).results?.A?.frames ?? [];
    expect(frames.length, "hubble_drop_total has series (metrics enabled + scraped)").toBeGreaterThan(
      0,
    );
  });
});

// Guards the prerequisites helm-template cannot check: dashboards registered, the Pyroscope datasource
// answering, alert rules loaded, and each metric family a panel reads present (ADR-0501).
// The RED check pins the stable otelhttp histogram, with le="0.5" a real 500ms bucket (ADR-0500).
test.describe("service observability POC (ADR-0501)", () => {
  let ctx: APIRequestContext;
  let promUid: string;

  test.beforeAll(async () => {
    ctx = await request.newContext({ ignoreHTTPSErrors: true, storageState: OPERATOR_STATE });
    const ds = await ctx.get(`${opsURL("grafana")}/api/datasources/name/Prometheus`);
    promUid = (await ds.json()).uid;
  });
  test.afterAll(async () => {
    await ctx?.dispose();
  });

  // Runs an instant PromQL query through Grafana's datasource proxy and reports
  // whether any series came back (frames are empty when nothing matches).
  async function promHasSeries(expr: string): Promise<boolean> {
    const res = await ctx.post(`${opsURL("grafana")}/api/ds/query`, {
      data: {
        from: "now-24h",
        to: "now",
        queries: [{ refId: "A", datasource: { type: "prometheus", uid: promUid }, expr, instant: true }],
      },
    });
    if (!res.ok()) {
      return false;
    }
    return (((await res.json()).results?.A?.frames ?? []) as unknown[]).length > 0;
  }

  // @smoke, unlike its neighbours (ADR-0601, ADR-0501): a day of exposure for a platform-contract regression is defensible, and for the dashboards someone opens during an incident it is not.
  test("every POC dashboard is registered with Grafana @smoke", async () => {
    const res = await ctx.get(`${opsURL("grafana")}/api/search?type=dash-db`);
    expect(res.ok(), "Grafana search API answers").toBeTruthy();
    const uids = ((await res.json()) as { uid: string }[]).map((d) => d.uid);
    expect(uids, "overview + detail + applications + components dashboards are provisioned").toEqual(
      expect.arrayContaining(["overview", "service-detail", "applications", "platform-components"]),
    );
  });

  test("Pyroscope datasource is provisioned and healthy", async () => {
    const ds = await ctx.get(`${opsURL("grafana")}/api/datasources/name/Pyroscope`);
    expect(ds.ok(), "Pyroscope datasource is provisioned").toBeTruthy();
    const { uid } = await ds.json();
    const health = await ctx.get(`${opsURL("grafana")}/api/datasources/uid/${uid}/health`);
    expect(health.ok(), "Pyroscope health endpoint reachable").toBeTruthy();
    expect((await health.json()).status, "Pyroscope answers from Grafana").toBe("OK");
  });

  test("kubeletstats CPU/memory series exist (resource panels)", async () => {
    expect(await promHasSeries('k8s_pod_cpu_usage{service_namespace="platform"}')).toBeTruthy();
    expect(await promHasSeries('k8s_pod_memory_working_set_bytes{service_namespace="platform"}')).toBeTruthy();
  });

  test("RED reads the stable otelhttp histogram (real 500ms bucket)", async () => {
    expect(await promHasSeries('http_server_request_duration_seconds_bucket{le="0.5"}')).toBeTruthy();
  });

  // otel-cluster's two jobs. k8s_cluster feeds the workload-health alerts and the Health row, and its OTLP push
  // is netpol-gated, which ClusterStateMetricsAbsent fires on.
  // The exporter scrapes guard their scrape config, the metrics-port ingress rule, and Temporal's delete_key.
  test("otel-cluster series exist: cluster state + component exporters", async () => {
    expect(await promHasSeries('k8s_deployment_desired{service_namespace="platform"}')).toBeTruthy();
    expect(await promHasSeries('cnpg_backends_total{service_name="postgres"}')).toBeTruthy();
    expect(await promHasSeries('service_requests_total{service_name="temporal"}')).toBeTruthy();
  });

  // The rule files must be loaded by Prometheus, not just committed (ADR-0500): this catches the ConfigMap, its
  // Argo app, the chart's rule_files and mount, and rule-file syntax.
  // @smoke because an alert that never fires is the difference between a slow incident and an unnoticed one.
  test("alert rules are loaded into Prometheus @smoke", async () => {
    const res = await ctx.get(
      `${opsURL("grafana")}/api/datasources/proxy/uid/${promUid}/api/v1/rules`,
    );
    expect(res.ok(), "Prometheus rules API answers via the Grafana proxy").toBeTruthy();
    const groups: { rules: { name: string }[] }[] = (await res.json()).data?.groups ?? [];
    const names = groups.flatMap((g) => g.rules.map((r) => r.name));
    expect(names, "committed alert rules are evaluating").toEqual(
      expect.arrayContaining([
        "ServiceHigh5xx",
        "PolicyDropsDetected",
        "DeploymentReplicasUnavailable",
        "ContainerRestartsSpiking",
        // Admission control (ADR-0104): the rule that fires when the thing checking
        // image provenance stops running.
        "KyvernoAdmissionControllerAbsent",
      ]),
    );
  });

  // Platform workloads only write stdout, so they reach Loki solely through the collector's filelog preset
  // (ADR-0500). Asserting distinct service_name values pins the hostPath mount, the receiver, the container
  // parser, and the k8sattributes inference. The agent is excluded: its receiver skips its own pod by design.
  test("platform workloads that only log to stdout reach Loki (filelog)", async () => {
    const ds = await ctx.get(`${opsURL("grafana")}/api/datasources/name/Loki`);
    expect(ds.ok(), "Loki datasource is provisioned").toBeTruthy();
    const { uid } = await ds.json();
    const start = `${(Date.now() - 24 * 3600 * 1000) * 1e6}`;
    const res = await ctx.get(
      `${opsURL("grafana")}/api/datasources/proxy/uid/${uid}/loki/api/v1/label/service_name/values?start=${start}`,
    );
    expect(res.ok(), "Loki label API answers via the Grafana proxy").toBeTruthy();
    const services: string[] = (await res.json()).data ?? [];
    expect(services, "stdout-only platform workloads have logs in Loki").toEqual(
      expect.arrayContaining(["postgres", "temporal", "lowdefy", "observability", "otel-cluster"]),
    );
  });

  // Marketing events are diverted out of the logs pipeline before Loki, because identity-bearing events in the log
  // store would breach ADR-0500's PII rule and ADR-0700 states review vigilance is not sufficient.
  // It asserts a negative, and fails the day someone emits marketing events without the split.
  test("no marketing.* event reaches the log store @smoke", async () => {
    const ds = await ctx.get(`${opsURL("grafana")}/api/datasources/name/Loki`);
    expect(ds.ok(), "Loki datasource is provisioned").toBeTruthy();
    const { uid } = await ds.json();
    const start = `${(Date.now() - 24 * 3600 * 1000) * 1e6}`;
    // Searching Loki for the literal `marketing.` matches its own audit trail, so the naive assertion passes once
    // and then accuses the platform of a leak that is its own search term.
    // `marke[t]ing\\.` cannot match itself, and the components whose job is logging request URLs are excluded.
    const query = encodeURIComponent(
      '{service_name=~".+", service_name!~"observability|otel-cluster|ory"} |~ "marke[t]ing\\\\."',
    );
    const res = await ctx.get(
      `${opsURL("grafana")}/api/datasources/proxy/uid/${uid}/loki/api/v1/query_range?query=${query}&start=${start}&limit=5`,
    );
    expect(res.ok(), "Loki query API answers via the Grafana proxy").toBeTruthy();
    const streams = (await res.json()).data?.result ?? [];
    expect(
      streams,
      "a marketing.* event in Loki means the routing connector is missing or bypassed (ADR-0700)",
    ).toHaveLength(0);
  });
});

// Hits the services east-west with a known inbound traceparent, so the trace id is fixed up front and there is no search race. The browser-driven equivalent is purchase.spec.ts.
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

  // A synthetic identity, because the suite reaches the service through a port-forward and supplies the headers the edge would inject. The org id only has to be well-formed.
  const BUYER_ID = "obs-e2e-buyer";
  const BUYER_ORG_ID = "org_01kztn9tsrea7b1597q3yjdeav";

  test("a checkout emits a stitched trace, correlated logs and metrics @smoke", async () => {
    test.setTimeout(180_000);
    const catalog = `http://127.0.0.1:${CATALOG_PORT}`;
    const orders = `http://127.0.0.1:${ORDERS_PORT}`;

    // Operator-authored product (X-User-Id admin-console holds group:operator, the
    // same subject the admin console writes as — ADR-0401).
    const productRes = await fetch(`${catalog}/products`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-user-id": "admin-console" },
      body: JSON.stringify({
        name: `obs-e2e-${Date.now()}`,
        price: { amount: "42.00", currency: "EUR" },
      }),
    });
    expect(productRes.ok, "operator can create a product").toBeTruthy();
    const productId = ((await productRes.json()) as { id: string }).id;

    // An order belongs to a buyer and to the org they act through (ADR-0304), so the two identity headers are what make it placeable at all.
    const { header, traceId } = newTraceparent();
    const orderRes = await fetch(`${orders}/orders`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        traceparent: header,
        "x-user-id": BUYER_ID,
        "x-org-id": BUYER_ORG_ID,
        "idempotency-key": `obs-e2e-${Date.now()}`,
      },
      body: JSON.stringify({ product_id: productId, quantity: 2 }),
    });
    expect(orderRes.status, "checkout accepted (202)").toBe(202);
    const orderId = ((await orderRes.json()) as { run_id: string }).run_id;

    // The saga is async: poll the order until it confirms (catalog lookup + payment
    // charge both succeeded — the reachability the netpol fix restored).
    await expect
      .poll(
        async () => {
          // The buyer reads their own order: `order#read` resolves through the owner
          // tuple the checkout saga wrote for this identity.
          const r = await fetch(`${orders}/orders/${orderId}`, {
            headers: { "x-user-id": BUYER_ID },
          });
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

    // Prometheus escapes OTLP dotted names to the classic underscore form, and RED reads the stable otelhttp histogram (ADR-0500).
    await expect
      .poll(async () => await promSeriesCount("orders_checkouts_started_total"), { timeout: 60_000 })
      .toBeGreaterThan(0);
    expect(await promSeriesCount("http_server_request_duration_seconds_count")).toBeGreaterThan(0);
    expect(await promSeriesCount("catalog_products_created_total")).toBeGreaterThan(0);
  });
});
