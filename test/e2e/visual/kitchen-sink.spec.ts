// Component visual regression against committed baselines, per ADR-0601 and ADR-0400.
import { expect, test } from "@playwright/test";
import { kitchenSinkSections } from "../fixtures/a11y";
import { BASE_URL, USER_STATE } from "../fixtures/env";

test.describe("visual regression @visual", () => {
  test.use({ storageState: USER_STATE });

  test("every kitchen-sink section matches its baseline", async ({ page }) => {
    await page.goto(`${BASE_URL}/devportal/kitchen-sink`);
    await expect(page.getByRole("heading", { name: "Design catalogue" })).toBeVisible();

    const sections = await kitchenSinkSections(page);
    // An empty page would pass with nothing checked. On a regression gate, that is worse than no gate: it reports coverage that does not exist.
    expect(sections.length, "kitchen sink rendered no primitive sections").toBeGreaterThan(0);

    for (const [index, title] of sections.entries()) {
      const section = page.locator(`main section:nth-of-type(${index + 1})`);
      await expect(section, `kitchen sink § ${title}`).toHaveScreenshot(
        `kitchen-sink-${index + 1}.png`,
        {
          // Animations in progress are the largest source of a diff that no change caused.
          animations: "disabled",
          // Antialiasing differs by a pixel or two between runs on the same machine. Anything larger is a real change.
          maxDiffPixelRatio: 0.01,
        },
      );
    }
  });
});
