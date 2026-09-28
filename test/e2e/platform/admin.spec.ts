// The Lowdefy admin console ops dashboard, on the same staged gauge as the others (ADR-0401, ADR-0306).
import { expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { OPERATOR, USER } from "../fixtures/identities";
import { register } from "../fixtures/kratos";
import { portForward } from "../fixtures/kube";

const CONSOLE = `${opsURL("lowdefy")}/`;
const PROMOTED_EMAIL = `promoted-${Date.now()}@e2e.localtest.me`;
const PROMOTED_PASSWORD = "Harbor-Quill-Meadow-7!";

test.describe("lowdefy ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("lowdefy");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("lowdefy");
  });

  test("gated: AAL2 operator passes the dashboard:lowdefy#view grant", async () => {
    await expectOperatorAllowed("lowdefy");
  });

  // The gauge: reusing the saved AAL2 session, the Lowdefy admin renders.
  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the admin dashboard paints @smoke", async ({ page }) => {
      await page.goto(CONSOLE);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // dashboard.yaml renders a Markdown "# Platform admin" heading.
      await expect(
        page.getByRole("heading", { name: "Platform admin" }),
      ).toBeVisible({ timeout: 30_000 });
    });
  });

  // The data gauge: if the console cannot reach catalog, or the grid binds the HTTP envelope instead of its body, the created row never appears.
  test.describe("products CRUD", () => {
    test.use({ storageState: OPERATOR_STATE });

    test("create, list, edit and delete a product @smoke", async ({ page }) => {
      const name = `e2e-widget-${Date.now()}`;
      const renamed = `${name}-v2`;
      const admin = opsURL("lowdefy");

      // Add: the standalone create page (Django "add" form). On success it redirects
      // to the changelist, where the new row is the confirmation — the assertion an
      // empty grid (the NetworkPolicy / `.data` / write-auth bugs) would fail.
      await page.goto(`${admin}/products_new`);
      await page.getByLabel(/^name$/i).fill(name);
      // Two fields, not one: a price is an amount AND a currency (ADR-0300), and the
      // admin generator renders the shared Money component as the pair.
      await page.getByLabel(/^price$/i).fill("42.00");
      await page.getByLabel(/^currency$/i).fill("EUR");
      await page.getByRole("button", { name: "Create", exact: true }).click();
      await expect(page).toHaveURL(/\/products$/, { timeout: 20_000 });
      await expect(page.getByText(name)).toBeVisible({ timeout: 30_000 });

      // Row-click opens the change page, prefilled from GET /products/{id}.
      await page.getByText(name).click();
      await expect(page).toHaveURL(/products_edit\?id=/, { timeout: 15_000 });
      await expect(page.getByLabel(/^name$/i)).toHaveValue(name, { timeout: 20_000 });

      // Edit and save; the success toast confirms the PUT resolved.
      await page.getByLabel(/^name$/i).fill(renamed);
      await page.getByRole("button", { name: "Save", exact: true }).click();
      await expect(page.getByText("Saved changes")).toBeVisible({ timeout: 20_000 });

      // The changelist reflects the edit: renamed present, original gone.
      await page.goto(`${admin}/products`);
      await expect(page.getByText(renamed)).toBeVisible({ timeout: 30_000 });
      await expect(page.getByText(name, { exact: true })).toHaveCount(0);

      // Delete from the change page redirects to the changelist, row removed.
      await page.getByText(renamed).click();
      await expect(page).toHaveURL(/products_edit\?id=/, { timeout: 15_000 });
      await page.getByRole("button", { name: "Delete", exact: true }).click();
      await expect(page).toHaveURL(/\/products$/, { timeout: 15_000 });
      await expect(page.getByText(renamed)).toHaveCount(0);
    });
  });

  // Rows come from Kratos admin via authz, a path that works only when authz can reach the Kratos admin API
  // (network-policies/30-ory.yaml). A paint-only check would pass on an empty grid, so this asserts the seeded
  // identities are present, then edits one to exercise the PUT write path (ADR-0401).
  test.describe("identities", () => {
    test.use({ storageState: OPERATOR_STATE });

    test("list shows seeded identities and an edit round-trips @smoke", async ({ page }) => {
      const admin = opsURL("lowdefy");

      // Changelist: the seeded operator and product user must both appear. An empty
      // grid — a stale authz image without /identities, a blocked Kratos admin call,
      // or the grid binding the HTTP envelope instead of `list.data` — fails here.
      await page.goto(`${admin}/identities`);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      await expect(page.getByText(OPERATOR.email)).toBeVisible({ timeout: 30_000 });
      await expect(page.getByText(USER.email)).toBeVisible({ timeout: 30_000 });

      // Row-click opens the change page, prefilled from GET /identities/{id}.
      await page.getByText(OPERATOR.email).first().click();
      await expect(page).toHaveURL(/identities_edit\?id=/, { timeout: 15_000 });
      const nameField = page.getByLabel(/^name$/i);
      await expect(nameField).toBeVisible({ timeout: 20_000 });
      const original = await nameField.inputValue();
      const renamed = `e2e-op-${Date.now()}`;

      // Edit the name and save; the success toast confirms the PUT resolved — proof
      // the operator identity header and OpenFGA grant let the write through.
      await nameField.fill(renamed);
      await page.getByRole("button", { name: "Save", exact: true }).click();
      await expect(page.getByText("Saved changes")).toBeVisible({ timeout: 20_000 });

      // The changelist reflects the edit (the write actually persisted to Kratos).
      await page.goto(`${admin}/identities`);
      await expect(page.getByText(renamed)).toBeVisible({ timeout: 30_000 });

      // Revert so the shared operator identity is left as found, and only when there was a name: the form rejects an empty one.
      if (original) {
        await page.getByText(OPERATOR.email).first().click();
        await expect(page).toHaveURL(/identities_edit\?id=/, { timeout: 15_000 });
        await page.getByLabel(/^name$/i).fill(original);
        await page.getByRole("button", { name: "Save", exact: true }).click();
        await expect(page.getByText("Saved changes")).toBeVisible({ timeout: 20_000 });
      }
    });
  });

  // Promotion is the one way to become an operator (ADR-0304): a self-registered user, promoted and demoted from the
  // identity page, whose toggle runs the SetOperator dual write. Kratos is read back after each save.
  test.describe("promote and demote an operator", () => {
    test.use({ storageState: OPERATOR_STATE });

    const operatorFlag = async (): Promise<unknown> => {
      const pf = await portForward("ory-kratos-admin", 4434, 80);
      try {
        const res = await fetch(
          `http://127.0.0.1:4434/admin/identities?credentials_identifier=${encodeURIComponent(PROMOTED_EMAIL)}`,
        );
        const list = (await res.json()) as Array<{ metadata_public?: { operator?: unknown } }>;
        return list[0]?.metadata_public?.operator ?? false;
      } finally {
        pf.stop();
      }
    };

    test.afterAll(async () => {
      const pf = await portForward("ory-kratos-admin", 4434, 80);
      try {
        const res = await fetch(
          `http://127.0.0.1:4434/admin/identities?credentials_identifier=${encodeURIComponent(PROMOTED_EMAIL)}`,
        );
        const list = res.ok ? ((await res.json()) as Array<{ id: string }>) : [];
        for (const hit of list) {
          await fetch(`http://127.0.0.1:4434/admin/identities/${hit.id}`, { method: "DELETE" });
        }
      } finally {
        pf.stop();
      }
    });

    test("the identity toggle promotes and demotes @smoke", async ({ browser, page }) => {
      const anon = await browser.newContext({ ignoreHTTPSErrors: true, storageState: undefined });
      try {
        await register(await anon.newPage(), PROMOTED_EMAIL, PROMOTED_PASSWORD);
      } finally {
        await anon.close();
      }

      const admin = opsURL("lowdefy");
      for (const want of [true, false]) {
        await page.goto(`${admin}/identities`);
        await page.getByText(PROMOTED_EMAIL).first().click({ timeout: 30_000 });
        await expect(page).toHaveURL(/identities_edit\?id=/, { timeout: 15_000 });
        const toggle = page.getByRole("switch");
        await expect(toggle).toBeVisible({ timeout: 20_000 });
        await toggle.click();
        await page.getByRole("button", { name: "Save", exact: true }).click();
        await expect(page.getByText("Saved changes")).toBeVisible({ timeout: 30_000 });
        expect(await operatorFlag(), `metadata_public.operator after saving ${want}`).toBe(want);
      }
    });
  });

  // The remaining generated pages (tools/admin-gen). Behind the AAL2 operator
  // session each must paint a page-specific control — proof the Lowdefy page
  // rendered rather than redirecting to login or stalling on an empty shell.
  test.describe("generated pages render", () => {
    test.use({ storageState: OPERATOR_STATE });

    const pages: Array<{ path: string; control: string; role: "button" | "text" }> = [
      { path: "/products", control: "Add product", role: "button" }, // changelist add
      { path: "/products_new", control: "Create", role: "button" }, // add form
      // Orgs has no add form: `POST /orgs` was withdrawn, because an org is created
      // by the registration workflow and never by hand. The changelist is what the
      // page is, so its own hint is the control that proves it painted.
      { path: "/orgs", control: "Click a row to edit.", role: "text" },
      // The money columns, since C5: an amount and its currency, not minor units.
      { path: "/orders", control: "Total", role: "text" }, // list-only grid header
      { path: "/charges", control: "Amount", role: "text" }, // list-only grid header
      { path: "/refundCharge", control: "Refund charge", role: "button" }, // action form
      { path: "/cancelOrder", control: "Cancel order", role: "button" }, // action form
    ];

    for (const p of pages) {
      test(`${p.path} paints @smoke`, async ({ page }) => {
        await page.goto(`${opsURL("lowdefy")}${p.path}`);
        await expect(page).not.toHaveURL(/\/auth\/login/);
        const control =
          p.role === "button"
            ? page.getByRole("button", { name: p.control })
            : page.getByText(p.control).first();
        await expect(control).toBeVisible({ timeout: 30_000 });
      });
    }
  });
});
