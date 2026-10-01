// The orders seam, per ADR-0400 and ADR-0701. It runs in the browser, so it has no `server-only` import.
import { order as fixtureOrder } from "@/fixtures/orders";
import { createBrowserClient } from "@/lib/server-fetch/client";
import { pollWorkflow, type WorkflowHandle } from "@/lib/server-fetch/workflow-handle";
import { fixturesEnabled } from "./mode";

export type OrderDraft = { product_id: string; quantity: number };
export type Order = { id: string; status: string };

type OrdersPaths = {
  "/orders": {
    post: {
      requestBody: { content: { "application/json": OrderDraft } };
      responses: { 202: { content: { "application/json": WorkflowHandle } } };
    };
  };
};

/** Enqueue the order. It resolves with the workflow handle, before the order settles. */
export async function startOrder(draft: OrderDraft): Promise<WorkflowHandle> {
  if (fixturesEnabled) {
    return fixtureOrder.handle;
  }
  const orders = createBrowserClient<OrdersPaths>();
  // One key per submit. So if the browser retries a request that already reached the service, it gets the order it created, not a second one, per ADR-0003.
  const { data, error } = await orders.POST("/orders", {
    body: draft,
    headers: { "Idempotency-Key": crypto.randomUUID() },
  });
  if (error || !data) {
    throw new Error("could not place the order");
  }
  return data;
}

/** Poll the enqueued order until the saga settles it, per ADR-0302. */
export async function awaitOrder(handle: WorkflowHandle): Promise<Order> {
  if (fixturesEnabled) {
    return fixtureOrder.settled;
  }
  return await pollWorkflow<Order>(handle);
}
