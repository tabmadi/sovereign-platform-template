import { describe, expect, test } from "bun:test";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ordersApi, server } from "@/test/msw";
import { renderWithProviders } from "@/test/render";
import Checkout from "./page";

const productId = "product_01h9xk2m4n8p6q3r5s7t9v0wbh";
const orderId = "order_01h9xk2m4n8p6q3r5s7t9v0wbh";

async function buy(product: string) {
  const user = userEvent.setup();
  renderWithProviders(<Checkout />);
  await user.type(screen.getByLabelText("Product"), product);
  await user.click(screen.getByRole("button", { name: "Buy" }));
}

describe("the checkout form", () => {
  test("a value that is not a product id shows the field error and sends nothing", async () => {
    await buy("order_01h9xk2m4n8p6q3r5s7t9v0wbh");

    expect(await screen.findByText("not a product id")).toBeTruthy();
    expect(screen.getByText("idle")).toBeTruthy();
  });

  test("a valid product id places the order and shows its settled status", async () => {
    server.use(
      ordersApi.ok(
        "post",
        "/orders",
        {
          id: orderId,
          run_id: "01h9xk2m4n8p6q3r5s7t9v0wbh",
          status: "running",
          result_url: `/api/orders/${orderId}`,
        },
        202,
      ),
      ordersApi.ok("get", "/orders/{id}", {
        id: orderId,
        product_id: productId,
        quantity: 1,
        total: { amount: "10.00", currency: "USD" },
        status: "confirmed",
      }),
    );

    await buy(productId);

    expect(await screen.findByText("confirmed")).toBeTruthy();
  });

  test("a refused order shows the error status", async () => {
    server.use(
      ordersApi.problem("post", "/orders", {
        type: "urn:problem-type:orders:out-of-stock",
        title: "Out of stock",
        status: 409,
      }),
    );

    await buy(productId);

    expect(await screen.findByText("error")).toBeTruthy();
  });
});
