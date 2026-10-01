// Browser helpers that drive the real self-service auth UI, not the API.
import { type Page, expect } from "@playwright/test";
import { authenticator } from "otplib";
import { BASE_URL } from "./env";

const init = (flow: string, query = "") => `${BASE_URL}/auth/self-service/${flow}/browser${query}`;

// KratosFlow renders a submit node as `<button name="method" value="...">`. The totp second factor has the same shape.
const submitFor = (method: string) => `button[name="method"][value="${method}"]`;

// Kratos refuses a code that it has seen before for an identity. Enrolment, the aal2 step-up, and a later login can fall in one 30-second window.
// Kratos then shows a message about the flow, not the code.
// So this remembers each code it gives out, and waits for the next window if the window has not changed.
const usedCodes = new Set<string>();
async function freshTotp(page: Page, secret: string): Promise<string> {
  let code = authenticator.generate(secret);
  if (usedCodes.has(code)) {
    await page.waitForTimeout((authenticator.timeRemaining() + 1) * 1000);
    code = authenticator.generate(secret);
  }
  usedCodes.add(code);
  return code;
}

// A */browser init answers 303 to the UI page, and the goto can report this as a harmless ERR_ABORTED.
// `auth-ratelimit` limits the auth routes to 10/min per source IP. The suite is one IP, so it waits for its turn.
// A retry repeats the whole step, because the 429 can hit the init or the flow fetch after it.
const RATE_LIMIT_WAIT_MS = 7_000;
export async function gotoFlow(page: Page, url: string, expectVisible?: string): Promise<void> {
  const navigate = async () => {
    await page.goto(url, { waitUntil: "domcontentloaded" }).catch((err: unknown) => {
      if (!String(err).includes("ERR_ABORTED")) {
        throw err;
      }
    });
  };
  if (!expectVisible) {
    await navigate();
    return;
  }
  await expect(async () => {
    await navigate();
    await expect(page.locator(expectVisible)).toBeVisible({ timeout: 8_000 });
  }).toPass({ timeout: 90_000, intervals: [RATE_LIMIT_WAIT_MS] });
}

// `gotoFlow` waits for the request that starts a flow. The same limit covers every form POST after it.
// Traefik answers a refused POST itself, so the next form is not on the page.
// A retry repeats the whole flow: a POST that Traefik refused never reached Kratos, so it created nothing.
async function throughRateLimit<T>(page: Page, flow: () => Promise<T>): Promise<T> {
  const deadline = Date.now() + 120_000;
  // One 429 has two forms: Traefik's bare body for a refused form POST, and the app's own error text for a refused flow fetch.
  const rateLimited = () =>
    page
      .locator("body")
      .innerText()
      .then(
        (text) =>
          text.trim() === "Too Many Requests" || /Could not start .*\. Try again\./.test(text),
      )
      .catch(() => false);
  for (;;) {
    let result: T;
    try {
      result = await flow();
    } catch (err) {
      if (!(await rateLimited()) || Date.now() > deadline) {
        throw err;
      }
      await page.waitForTimeout(RATE_LIMIT_WAIT_MS);
      continue;
    }
    if (!(await rateLimited())) {
      return result;
    }
    if (Date.now() > deadline) {
      throw new Error("auth-ratelimit kept answering 429 for the whole retry budget");
    }
    await page.waitForTimeout(RATE_LIMIT_WAIT_MS);
  }
}

async function notOnLogin(page: Page): Promise<void> {
  await expect(page).not.toHaveURL(/\/auth\/login/, { timeout: 20_000 });
}

// Wait until the Kratos session cookie is set in the context. notOnLogin proves only that the URL left the login page.
// Without this wait, a later flow init, for example settings, can run before the Set-Cookie and go to the return URL.
async function waitForSession(page: Page): Promise<void> {
  await expect
    .poll(async () => (await page.context().cookies()).some((c) => c.name === "ory_kratos_session"), {
      timeout: 15_000,
    })
    .toBe(true);
}

// Neither signal above proves that the redirect chain ended. notOnLogin is true at its start, and waitForSession returns in the middle.
// A caller that navigates after either one races a redirect, and the redirect cancels the goto.
// This waits for a stable URL, not a specific URL, so a caller that passes return_to does not hang.
async function settle(page: Page): Promise<void> {
  await expect
    .poll(
      async () => {
        const before = page.url();
        await page.waitForTimeout(200);
        return page.url() === before;
      },
      { timeout: 15_000 },
    )
    .toBe(true);
}

// passwordLogin completes the first-factor AAL1 login through the rendered form.
export async function passwordLogin(page: Page, email: string, password: string): Promise<void> {
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("login"), 'input[name="identifier"]');
    await page.fill('input[name="identifier"]', email);
    await page.fill('input[name="password"]', password);
    await page.click(submitFor("password"));
    await notOnLogin(page);
  });
  await waitForSession(page);
  await settle(page);
}

// This is the only path that fires the registration `after` web_hook. Identities from the admin API skip self-service flows and get no personal org.
// Registration has two steps: traits, then credentials. One form for both hangs on a password field that is not there yet.
export async function register(page: Page, email: string, password: string): Promise<void> {
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("registration"), 'input[name="traits.email"]');
    await page.fill('input[name="traits.email"]', email);
    await page.click(submitFor("profile"));

    await page.locator('input[name="password"]').waitFor({ state: "visible", timeout: 20_000 });
    await page.fill('input[name="password"]', password);
    await page.click(submitFor("password"));
    // Kratos shows the register form again with the message on any failure, including a blocking orgs web_hook. So leaving the form is the success signal.
    await expect(page).not.toHaveURL(/\/auth\/register/, { timeout: 30_000 });
  });
}

// Drives the same two-step form as `register`, for the opposite outcome. It returns the rendered text, so the caller can check which rule fired.
// A test that asserts only a rejection lets a dead breach check hide.
export async function registerExpectingRejection(
  page: Page,
  email: string,
  password: string,
): Promise<string> {
  return throughRateLimit(page, async () => {
    await gotoFlow(page, init("registration"), 'input[name="traits.email"]');
    await page.fill('input[name="traits.email"]', email);
    await page.click(submitFor("profile"));

    await page.locator('input[name="password"]').waitFor({ state: "visible", timeout: 20_000 });
    await page.fill('input[name="password"]', password);
    await page.click(submitFor("password"));
    return readRejection(page);
  });
}

// The rejection assertions are a separate function, so the retry above wraps the whole flow.
async function readRejection(page: Page): Promise<string> {
  // Staying on /auth/register is the rejection signal. The message is on the password node, so this reads the page and does not depend on that markup.
  // Leaving the form means that the policy accepted the credential. The raw diff would look like a routing bug, so the assertion names the cause.
  await expect(
    page,
    "password was ACCEPTED: the policy that must refuse it did not fire",
  ).toHaveURL(/\/auth\/register/, { timeout: 30_000 });
  await page.locator('input[name="password"]').waitFor({ state: "visible", timeout: 20_000 });
  return page.locator("body").innerText();
}

// An operator has TOTP enrolled. This answers the second factor on the same /auth/login flow and ends with an AAL2 session. passwordLogin expects a password-only identity.
export async function operatorLogin(
  page: Page,
  email: string,
  password: string,
  secret: string,
): Promise<void> {
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("login"), 'input[name="identifier"]');
    await page.fill('input[name="identifier"]', email);
    await page.fill('input[name="password"]', password);
    await page.click(submitFor("password"));
  });

  // With a second factor enrolled and required_aal highest_available, Kratos shows the TOTP challenge on the same /auth/login URL. A password-only identity redirects away.
  const totp = page.locator('input[name="totp_code"]');
  const prompted = await totp
    .waitFor({ state: "visible", timeout: 15_000 })
    .then(() => true)
    .catch(() => false);
  if (prompted) {
    await totp.fill(await freshTotp(page, secret));
    await page.click(submitFor("totp"));
  }
  await notOnLogin(page);
  await waitForSession(page);
  await settle(page);

  // An operator has a second factor, so any level below aal2 is a failed step-up. A 429 on the aal2 continuation shows `Could not start sign-in`, not the TOTP form.
  // The prompt then never appears, and the AAL1 session shows much later as a dashboard title that reads `Platform`.
  await expect(async () => {
    if ((await sessionAal(page)) !== "aal2") {
      await ensureAal2(page, secret);
      await settle(page);
    }
    expect(await sessionAal(page)).toBe("aal2");
  }).toPass({ timeout: 90_000, intervals: [RATE_LIMIT_WAIT_MS] });
}

// sessionAal reads the AAL that Kratos records for the browser session. It is the only authority on whether a step-up happened. The URL after a login does not show it.
// It returns null when there is no session.
async function sessionAal(page: Page): Promise<string | null> {
  const res = await page.request.get(`${BASE_URL}/auth/sessions/whoami`, {
    failOnStatusCode: false,
  });
  if (!res.ok()) {
    return null;
  }
  const body = (await res.json()) as { authenticator_assurance_level?: string };
  return body.authenticator_assurance_level ?? null;
}

// enrolTotp enrols a TOTP second factor through the settings flow. It reads the secret that Kratos generates, rendered as the font-mono text node, and verifies a code.
// It returns the secret, so a later AAL2 login can generate valid codes.
export async function enrolTotp(page: Page): Promise<string> {
  const secretNode = page.locator("p.font-mono").first();
  // Init again if the flow goes to the return URL before the form renders.
  await expect(async () => {
    await gotoFlow(page, init("settings"));
    await expect(secretNode).toBeVisible({ timeout: 8_000 });
  }).toPass({ timeout: 40_000 });
  const secret = (await secretNode.innerText()).replace(/\s+/g, "");
  await page.fill('input[name="totp_code"]', await freshTotp(page, secret));
  await page.click(submitFor("totp"));
  // Settings reloads with the factor enrolled, and the secret node disappears.
  await expect(secretNode).toBeHidden({ timeout: 20_000 });
  return secret;
}

// Completing TOTP enrolment in a privileged settings flow already raises the session, so the ?aal=aal2 login usually has nothing to step up.
export async function ensureAal2(page: Page, secret: string): Promise<void> {
  await gotoFlow(page, init("login", "?aal=aal2"));
  const totp = page.locator('input[name="totp_code"]');
  const prompted = await totp
    .waitFor({ state: "visible", timeout: 8_000 })
    .then(() => true)
    .catch(() => false);
  if (prompted) {
    await totp.fill(await freshTotp(page, secret));
    await page.click(submitFor("totp"));
  }
  await notOnLogin(page);
}

// Drives the real recovery form. This form makes the Kratos courier send a message, per ADR-0307.
// `use: code` means that the mail carries a six-digit code, and the flow stays open until the user enters it.
export async function startRecovery(page: Page, email: string): Promise<void> {
  // This uses the same wrapper as every other flow that POSTs. `auth-ratelimit` covers the submit and the init. A refused POST never reached Kratos, so a new run from the init is safe.
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("recovery"), 'input[name="email"]');
    await page.fill('input[name="email"]', email);
    await page.click(submitFor("code"));
    // Enumeration protection shows the same code form for an address with no account. So this proves that the flow moved, not that a mail was sent.
    await page.locator('input[name="code"]').waitFor({ state: "visible", timeout: 30_000 });
  });
}
