// The full purchase scenario, end to end through the real UIs (ADR-0601).
import { expect, test } from "@playwright/test";
import { BASE_URL, OPERATOR_STATE, opsURL } from "../fixtures/env";
import { portForward } from "../fixtures/kube";
import { register, passwordLogin } from "../fixtures/kratos";
import { tempoSearchByOrderId, TEMPO_PORT, tempoTraceServices } from "../fixtures/observability";

const KRATOS_ADMIN = "http://127.0.0.1:4434";
// Self-service registration enforces the password policy (min 12, unbreached,
// dissimilar to the address) — same shape the registration spec uses.
const SHOPPER_EMAIL = `shopper-${Date.now()}@e2e.localtest.me`;
const SHOPPER_PASSWORD = "Meadow-Cipher-Walnut-42!";
const PRODUCT_NAME = `e2e-purchase-${Date.now()}`;

test.describe("full purchase scenario", () => {
  const CATALOG_PORT = 18091;
  const ORDERS_PORT = 18092;
  let stopCatalog: () => void;
  let stopOrders: () => void;
  let stopTempo: () => void;
  let productId = "";

  test.beforeAll(async () => {
    ({ stop: stopCatalog } = await portForward("catalog-server", CATALOG_PORT, 80));
    ({ stop: stopOrders } = await portForward("orders-server", ORDERS_PORT, 80));
    ({ stop: stopTempo } = await portForward("tempo", TEMPO_PORT, 3200));
  });

  test.afterAll(async () => {
    // Delete the product (operator write) and the shopper identity (Kratos admin),
    // so a re-run starts clean. Orders have no delete endpoint; a stale confirmed
    // row is harmless.
    try {
      if (productId) {
        await fetch(`http://127.0.0.1:${CATALOG_PORT}/products/${productId}`, {
          method: "DELETE",
          headers: { "x-user-id": "admin-console" },
        });
      }
    } catch {
      // best-effort cleanup
    }
    stopCatalog?.();
    stopOrders?.();
    stopTempo?.();

    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      const res = await fetch(
        `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(SHOPPER_EMAIL)}`,
      );
      if (res.ok) {
        const list = (await res.json()) as Array<{ id: string; traits?: { email?: string } }>;
        const hit = list.find((i) => i.traits?.email === SHOPPER_EMAIL);
        if (hit) {
          await fetch(`${KRATOS_ADMIN}/admin/identities/${hit.id}`, { method: "DELETE" });
        }
      }
    } finally {
      pf.stop();
    }
  });

  // @smoke because step 2 is, and step 2 hands over `productId` through the closure. `test:smoke` selects by --grep, which filters per test and does not follow that dependency.
  test.describe("operator adds a product", () => {
    test.use({ storageState: OPERATOR_STATE });

    test("via the admin console add-product page @smoke", async ({ page }) => {
      await page.goto(`${opsURL("lowdefy")}/products_new`);
      await page.getByLabel(/^name$/i).fill(PRODUCT_NAME);
      // Two fields, not one: a price is an amount AND a currency (ADR-0300), and the
      // admin generator renders the shared Money component as the pair.
      await page.getByLabel(/^price$/i).fill("42.00");
      await page.getByLabel(/^currency$/i).fill("EUR");
      await page.getByRole("button", { name: "Create", exact: true }).click();
      await expect(page).toHaveURL(/\/products$/, { timeout: 20_000 });
      await expect(page.getByText(PRODUCT_NAME)).toBeVisible({ timeout: 30_000 });

      // Resolve the new product's id from catalog (the checkout form takes a UUID).
      const res = await fetch(`http://127.0.0.1:${CATALOG_PORT}/products`);
      const products = (await res.json()) as Array<{ id: string; name: string }>;
      productId = products.find((p) => p.name === PRODUCT_NAME)?.id ?? "";
      expect(productId, "created product resolvable in catalog").toBeTruthy();
    });
  });

  // Steps 2–4: a brand-new shopper registers, logs in, buys, and the purchase is
  // observable. A fresh, isolated context (no operator storageState) — the shopper
  // is a different human in a different app.
  test("shopper registers, checks out, and the order is traced end to end @smoke", async ({
    browser,
  }) => {
    // The config's 60s default is a per-step budget, and this test's own waits exceed it: the saga has 60s to settle and Tempo 90s to make the trace searchable.
    test.setTimeout(240_000);
    expect(productId, "product from step 1").toBeTruthy();
    const ctx = await browser.newContext({ ignoreHTTPSErrors: true, storageState: undefined });
    try {
      const page = await ctx.newPage();

      // Register then log in (registration leaves no session by design).
      await register(page, SHOPPER_EMAIL, SHOPPER_PASSWORD);
      await passwordLogin(page, SHOPPER_EMAIL, SHOPPER_PASSWORD);

      // Buy the product on the storefront checkout.
      await page.goto(`${BASE_URL}/panel/checkout`);
      await page.locator('input[name="product_id"]').fill(productId);
      await page.getByRole("button", { name: "Buy" }).click();

      // The status badge settles on the terminal order status; "confirmed" means the
      // saga reached payment and back (catalog lookup + charge both succeeded).
      await expect(page.getByText("confirmed", { exact: true })).toBeVisible({ timeout: 60_000 });
    } finally {
      await ctx.close();
    }

    // Listing every order is operator-gated (ADR-0304), so this asserts the console's service identity the way the console does. Port-forwarded, so the edge never strips the header.
    const ordersRes = await fetch(`http://127.0.0.1:${ORDERS_PORT}/orders`, {
      headers: { "x-user-id": "admin-console" },
    });
    const orders = (await ordersRes.json()) as Array<{ id: string; product_id: string; status: string }>;
    const mine = orders.filter((o) => o.product_id === productId);
    expect(mine.length, "checkout created an order for this product").toBeGreaterThan(0);
    const orderId = mine[mine.length - 1].id;

    let services: string[] = [];
    await expect
      .poll(
        async () => {
          const traceId = await tempoSearchByOrderId(orderId);
          if (!traceId) {
            return false;
          }
          services = await tempoTraceServices(traceId);
          return ["orders", "catalog", "payment"].every((s) => services.includes(s));
        },
        { timeout: 90_000, intervals: [2000, 3000, 5000] },
      )
      .toBe(true);
    expect(services).toEqual(expect.arrayContaining(["orders", "catalog", "payment"]));
  });
});
