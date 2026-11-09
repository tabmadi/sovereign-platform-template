import { describe, expect, test } from "bun:test";
import { ordersApi, server } from "@/test/msw";
import { awaitOrder, startOrder } from "./orders";

const handle = {
  id: "order_01h9xk2m4n8p6q3r5s7t9v0wbh",
  run_id: "01h9xk2m4n8p6q3r5s7t9v0wbh",
  status: "running",
  result_url: "/api/orders/order_01h9xk2m4n8p6q3r5s7t9v0wbh",
} as const;

const draft = { product_id: "product_01h9xk2m4n8p6q3r5s7t9v0wbh", quantity: 1 };

describe("the orders seam", () => {
  test("a started order answers the workflow handle", async () => {
    server.use(ordersApi.ok("post", "/orders", handle, 202));

    expect(await startOrder(draft)).toEqual(handle);
  });

  test("a refused order throws", async () => {
    server.use(
      ordersApi.problem("post", "/orders", {
        type: "urn:problem-type:orders:out-of-stock",
        title: "Out of stock",
        status: 409,
      }),
    );

    await expect(startOrder(draft)).rejects.toThrow("could not place the order");
  });

  test("an order resolves when the poll reaches a terminal status", async () => {
    server.use(
      ordersApi.ok("get", "/orders/{id}", {
        id: handle.id,
        product_id: draft.product_id,
        quantity: 1,
        total: { amount: "10.00", currency: "USD" },
        status: "confirmed",
      }),
    );

    expect((await awaitOrder(handle)).status).toBe("confirmed");
  });
});
