// Every ops dashboard sits behind the same gate (ADR-0306): denied without a session, forbidden to an AAL1 product
// session, allowed to an AAL2 operator. One table, so a new tool is one row rather than a copied file.
import { expect, test } from "@playwright/test";
import { expectAal1Forbidden, expectOperatorAllowed, expectUnauthenticatedDenied } from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";

// `title` is the document title the tool's SPA sets once it paints; a tool without one is proven by its own spec.
const TOOLS: Array<{ tool: string; title?: RegExp }> = [
  { tool: "argocd", title: /Argo CD/ },
  { tool: "headlamp", title: /Headlamp/ },
  { tool: "hubble", title: /Hubble/ },
  { tool: "pgweb", title: /pgweb/i },
  { tool: "temporal", title: /Workflows|Temporal/ },
  { tool: "seaweedfs", title: /SeaweedFS Admin/ },
  { tool: "grafana" },
  { tool: "mailpit" },
  { tool: "lowdefy" },
];

for (const { tool, title } of TOOLS) {
  test.describe(`${tool} ops dashboard`, () => {
    test("gated: unauthenticated is denied", async () => {
      await expectUnauthenticatedDenied(tool);
    });

    test("gated: AAL1 product session is forbidden", async () => {
      await expectAal1Forbidden(tool);
    });

    test(`gated: AAL2 operator passes the dashboard:${tool}#view grant`, async () => {
      await expectOperatorAllowed(tool);
    });

    if (title) {
      test.describe("renders behind AAL2", () => {
        test.use({ storageState: OPERATOR_STATE });
        test("paints at the subdomain root", async ({ page }) => {
          await page.goto(`${opsURL(tool)}/`);
          await expect(page).not.toHaveURL(/\/auth\/login/);
          await expect(page).toHaveTitle(title, { timeout: 30_000 });
        });
      });
    }
  });
}
