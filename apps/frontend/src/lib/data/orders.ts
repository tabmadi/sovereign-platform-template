// The orders seam (ADR-0400, ADR-0701). Browser-side, so no `server-only` import:
// the checkout form is a client component and mutates through the edge.
//
// Two functions rather than one, because the screen has something to say between
// them: the POST returns a handle the user is shown before the workflow settles.
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

/** Enqueue the order. Resolves with the workflow handle, before it settles. */
export async function startOrder(draft: OrderDraft): Promise<WorkflowHandle> {
  if (fixturesEnabled) {
    return fixtureOrder.handle;
  }
  const orders = createBrowserClient<OrdersPaths>();
  // One key per submit, so the browser retrying a request that already reached the
  // service gets the order it created rather than a second one (ADR-0003).
  const { data, error } = await orders.POST("/orders", {
    body: draft,
    headers: { "Idempotency-Key": crypto.randomUUID() },
  });
  if (error || !data) {
    throw new Error("could not place the order");
  }
  return data;
}

/** Poll the enqueued order until the saga settles it (ADR-0302). */
export async function awaitOrder(handle: WorkflowHandle): Promise<Order> {
  if (fixturesEnabled) {
    return fixtureOrder.settled;
  }
  return await pollWorkflow<Order>(handle);
}
