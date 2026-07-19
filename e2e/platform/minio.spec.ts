// MinIO console operator dashboard (ADR-0011, ADR-0016) — non-prod object store,
// gated at s3.ops.<host> (dashboard:s3#view) and rendering behind a real
// AAL2 operator session. Like Grafana, the console keeps its own login behind the
// Kratos gate, so the gauge asserts its shell paints, not a post-login view.
import { expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";

const MINIO = `${opsURL("s3")}/`;

test.describe("s3 ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("s3");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("s3");
  });

  test("gated: AAL2 operator passes the dashboard:s3#view grant", async () => {
    await expectOperatorAllowed("s3");
  });

  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the console shell paints at the subdomain root", async ({ page }) => {
      await page.goto(MINIO);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // The MinIO Console SPA mounts at root and sets its document title.
      await expect(page).toHaveTitle(/MinIO/, { timeout: 30_000 });
    });
  });
});
