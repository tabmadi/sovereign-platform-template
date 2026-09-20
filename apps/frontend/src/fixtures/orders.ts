/**
 * Orders fixtures (ADR-0701), read only by `lib/data/orders.ts`. The handle and the settled resource are both
 * fixed, so a screenshot of a design-time checkout means something.
 */
export const order = {
  handle: {
    id: "order_01h9xk2m4n8p6q3r5s7t9v0wbh",
    run_id: "01h9xk2m4n8p6q3r5s7t9v0wbh",
    status: "running",
    result_url: "/api/orders/order_01h9xk2m4n8p6q3r5s7t9v0wbh",
  },
  settled: { id: "order_01h9xk2m4n8p6q3r5s7t9v0wbh", status: "confirmed" },
} as const;
