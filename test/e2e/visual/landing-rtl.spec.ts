// The mirrored layout, pinned (ADR-0400, ADR-0601).
import { expect, test } from "@playwright/test";
import { rtlURL } from "../fixtures/env";

test.describe("visual regression @visual", () => {
  test("the landing page matches its right-to-left baseline", async ({ page }) => {
    await page.goto(rtlURL());
    await expect(page.locator("html")).toHaveAttribute("dir", "rtl");

    await expect(page).toHaveScreenshot("landing-rtl.png", {
      animations: "disabled",
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    });
  });
});
