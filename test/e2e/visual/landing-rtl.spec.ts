// The mirrored layout, pinned (ADR-0400, ADR-0601).
//
// One baseline, deliberately: the landing page carries the shapes a mirror gets
// wrong — a heading, a list of links, and a control with an icon — and it composes
// no live data, so what the baseline pins is the direction rather than a fixture.
//
// Why this exists at all: the copy being translated is checked by `lint:i18n`, and
// axe checks the mirrored page renders accessibly. Neither can see a layout that is
// merely WRONG when mirrored — a margin on the wrong side, a chevron pointing out of
// the card. A picture can.
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
