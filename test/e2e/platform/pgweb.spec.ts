// The pgweb database inspector dashboard: opt-in, gated at the ops origin (ADR-0401, ADR-0306).
import { expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";

const PGWEB = `${opsURL("pgweb")}/`;

test.describe("pgweb ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("pgweb");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("pgweb");
  });

  test("gated: AAL2 operator passes the dashboard:pgweb#view grant", async () => {
    await expectOperatorAllowed("pgweb");
  });

  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the pgweb SPA paints at the subdomain root", async ({ page }) => {
      await page.goto(PGWEB);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // pgweb mounts its SPA at root and titles the document "pgweb".
      await expect(page).toHaveTitle(/pgweb/i, { timeout: 30_000 });
    });
  });
});
