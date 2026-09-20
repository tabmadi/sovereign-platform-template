// The Hubble service-map dashboard, gated at the ops origin (ADR-0306, ADR-0501).
import { expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";

const HUBBLE = `${opsURL("hubble")}/`;

test.describe("hubble ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("hubble");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("hubble");
  });

  test("gated: AAL2 operator passes the dashboard:hubble#view grant", async () => {
    await expectOperatorAllowed("hubble");
  });

  // The "operator but missing this tool's grant" fine gate is unit-tested in
  // services/authz/internal/decision — once every routed dashboard is granted to
  // group:operator, no routed-but-ungranted tool remains to assert it at the edge.

  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the flow-map paints at the subdomain root", async ({ page }) => {
      await page.goto(HUBBLE);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // hubble-ui sets the document title to "Hubble" and mounts its SPA at root.
      await expect(page).toHaveTitle(/Hubble/, { timeout: 30_000 });
    });
  });
});
