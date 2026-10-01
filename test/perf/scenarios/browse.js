// Read-path load: the catalog browse journey, per ADR-0601. It calls `GET /api/products`, the list that every storefront page reads, and `GET /api/products/{id}`, an indexed single-row read.
// Requests go through the edge, so each pays Traefik routing and the Oathkeeper forward-auth hop, per ADR-0305. Both reads are unauthenticated: catalog gates only writes, so no login cost.
// This path is cheap per request, so it saturates the EDGE and the Postgres connection pool before catalog itself. That ceiling is what it exists to find.

// `ListProducts` is `order by created_at desc limit 100`, so the RESPONSE never has more than 100 rows. Seeding changes only the server side:
// `created_at` has no index, so every list request sorts the whole table. That cost grows with the row count, and the response size does not.
// So record the seeded row count with any latency number.

import { sleep } from "k6";
import http from "k6/http";
import { Trend } from "k6/metrics";
import { expectJSON, expectStatus } from "../lib/checks.js";
import { API, options as buildOptions, summaryTrailer } from "../lib/config.js";

// The rows that the list endpoint returned at the start of the run, as a metric, so a captured result carries its own context.
// Because of `limit 100`, it stops at 100 and is NOT the table size. It shows whether the list response was full, from a big sorted table, or short, from an almost empty one.
const pageSize = new Trend("catalog_page_size");

export const options = buildOptions("browse", 1, {
  // Budgets, not SLOs, per ADR-0601. They are large enough that a passing run means no regression, not only a run that looks like idle.
  http_req_failed: ["rate<0.01"],
  "http_req_duration{endpoint:list_products}": ["p(95)<800"],
  "http_req_duration{endpoint:get_product}": ["p(95)<400"],
  checks: ["rate>0.99"],
});

// setup runs once, before any VU. It finds the product ids that the VUs read, and fails the whole run early if the catalog is empty.
// Otherwise every iteration would get 404, and the run would report a fast error rate.
export function setup() {
  const res = http.get(`${API}/products`, { tags: { endpoint: "list_products" } });
  if (res.status !== 200) {
    throw new Error(`catalog unreachable at ${API}/products: HTTP ${res.status}`);
  }
  const products = res.json();
  if (!Array.isArray(products) || products.length === 0) {
    throw new Error("catalog is empty. Run `mise run perf:seed` first, or this measures 404s");
  }
  return { ids: products.map((p) => p.id), size: products.length };
}

export default function browse(data) {
  pageSize.add(data.size);

  // 1. The list page.
  const list = http.get(`${API}/products`, {
    tags: { endpoint: "list_products" },
  });
  expectStatus(list, 200, "list products");

  // Think time. Without it, a VU is a tight loop, which measures how fast one connection runs, not how the system behaves under N users.
  sleep(0.5 + Math.random());

  // 2. A detail page for a random product from the list.
  const id = data.ids[Math.floor(Math.random() * data.ids.length)];
  const detail = http.get(`${API}/products/${id}`, {
    tags: { endpoint: "get_product" },
  });
  if (expectStatus(detail, 200, "get product")) {
    // The price is an object with a decimal STRING amount, never a number, per ADR-0300.
    // A shape check here catches a spec regression that a status code does not show.
    expectJSON(
      detail,
      "get product",
      (p) =>
        p.id === id && typeof p.price?.amount === "string" && typeof p.price?.currency === "string",
    );
  }

  sleep(0.5 + Math.random());
}

// teardown, not handleSummary: a handleSummary REPLACES k6's built-in summary table. A custom table needs a lot of formatting code
// or a remote jslib import, which is a supply-chain dependency for looks. Printing the caveat here keeps the real summary below it.
export function teardown(data) {
  console.log(
    `browse: the list endpoint returned ${data.ids.length} rows, limit 100${summaryTrailer()}`,
  );
}
