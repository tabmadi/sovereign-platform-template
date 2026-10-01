// The Grafana operator dashboard, on the staged chain that finds where a failure is, per ADR-0306.
import fs from "node:fs";
import { expect, test } from "@playwright/test";
import { OPERATOR_STATE, OPERATOR_TOTP_FILE, opsURL } from "../fixtures/env";
import { OPERATOR } from "../fixtures/identities";
import { operatorLogin } from "../fixtures/kratos";

const GRAFANA = `${opsURL("grafana")}/`;

test.describe("grafana ops dashboard", () => {
  // The real end-to-end auth flow from a new context, not from a pre-seeded session.
  test("login: operator authenticates through Kratos with the AAL2 step-up @smoke", async ({
    browser,
  }) => {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    // An unauthenticated request to the dashboard redirects an html browser to Kratos.
    await page.goto(GRAFANA);
    await expect(page).toHaveURL(/\/auth\/login/);
    // Log in for real: the password for AAL1, then the TOTP second factor for AAL2.
    const secret = fs.readFileSync(OPERATOR_TOTP_FILE, "utf8").trim();
    await operatorLogin(page, OPERATOR.email, OPERATOR.password, secret);
    // After authentication, the dashboard renders.
    await page.goto(GRAFANA);
    await expect(page).toHaveTitle(/Grafana/, { timeout: 30_000 });
    await ctx.close();
  });

  // The gauge: with the saved AAL2 session, the UI paints.
  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("a dashboard view paints @smoke", async ({ page }) => {
      await page.goto(GRAFANA);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      await expect(page).toHaveTitle(/Grafana/, { timeout: 30_000 });
    });
  });
});
