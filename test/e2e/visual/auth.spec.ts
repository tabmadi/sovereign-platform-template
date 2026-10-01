// The one composed route with a baseline, per ADR-0601.
import { expect, test } from "@playwright/test";
import { LOGIN_URL } from "../fixtures/env";
import { gotoFlow } from "../fixtures/kratos";

test.describe("visual regression @visual", () => {
  test("the login page matches its baseline", async ({ page }) => {
    // `gotoFlow`, not a bare goto: this route starts a Kratos flow and is behind `auth-ratelimit`. A bare goto can capture `Could not start sign-in` and not the form.
    await gotoFlow(page, LOGIN_URL, 'input[name="identifier"]');
    await expect(page.getByRole("button", { name: /sign in|log in/i })).toBeVisible();

    await expect(page).toHaveScreenshot("auth-login.png", {
      animations: "disabled",
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    });
  });
});
