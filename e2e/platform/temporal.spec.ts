// Temporal Web UI operator dashboard (ADR-0017) — gated at workflows.ops.<host>
// (dashboard:workflows#view) and the namespace view renders behind a real AAL2
// operator session.
import { expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";

const TEMPORAL = `${opsURL("workflows")}/`;

test.describe("workflows ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("workflows");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("workflows");
  });

  test("gated: AAL2 operator passes the dashboard:workflows#view grant", async () => {
    await expectOperatorAllowed("workflows");
  });

  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the namespace view paints", async ({ page }) => {
      await page.goto(TEMPORAL);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // temporalio/ui lands on the default namespace's workflows view, whose SPA
      // title is "Workflows | <namespace>".
      await expect(page).toHaveTitle(/Workflows|Temporal/, { timeout: 30_000 });
    });
  });
});
