// The orders seam, per ADR-0400 and ADR-0701. It runs in the browser, so it has no `server-only` import.
import type { components, paths } from "@sdks/orders";
import { handle as fixtureHandle, settled as fixtureSettled } from "@/fixtures/orders";
import { createBrowserClient } from "@/lib/server-fetch/client";
import { pollWorkflow, type WorkflowHandle } from "@/lib/server-fetch/workflow-handle";
import { fixturesEnabled } from "./mode";

export type OrderDraft = components["schemas"]["CheckoutInput"];
export type Order = components["schemas"]["Order"];

/** Enqueue the order. It resolves with the workflow handle, before the order settles. */
export async function startOrder(draft: OrderDraft): Promise<WorkflowHandle> {
  if (fixturesEnabled) {
    return fixtureHandle;
  }
  const orders = createBrowserClient<paths>();
  // One key per submit. So if the browser retries a request that already reached the service, it gets the order it created, not a second one, per ADR-0003.
  const { data, error } = await orders.POST("/orders", {
    body: draft,
    params: { header: { "Idempotency-Key": crypto.randomUUID() } },
  });
  if (error || !data) {
    throw new Error("could not place the order");
  }
  return data;
}

/** Poll the enqueued order until the saga settles it, per ADR-0302. */
export async function awaitOrder(handle: WorkflowHandle): Promise<Order> {
  if (fixturesEnabled) {
    return fixtureSettled;
  }
  return await pollWorkflow<Order>(handle);
}
