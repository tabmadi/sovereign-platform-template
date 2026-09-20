// Browser helpers that drive the real self-service auth UI rather than the API.
import { type Page, expect } from "@playwright/test";
import { authenticator } from "otplib";
import { BASE_URL } from "./env";

const init = (flow: string, query = "") => `${BASE_URL}/auth/self-service/${flow}/browser${query}`;

// The password-method submit button (KratosFlow renders submit nodes as
// <button name="method" value="...">). Same shape for the totp second factor.
const submitFor = (method: string) => `button[name="method"][value="${method}"]`;

// Kratos refuses a code it has already seen for an identity, and enrolment, the aal2 step-up and a later login
// can land in one 30-second window. It re-renders the flow with a message about the flow, not the code.
// So: remember what was handed out, and wait for the next window if it has not rolled.
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

// A */browser init 303s to the UI page, which can surface as a benign ERR_ABORTED on the goto.
// `auth-ratelimit` caps the auth routes at 10/min per source IP and the suite is one IP, so it waits its turn.
// The unit of retry is the whole step: the 429 can land on the init or on the flow fetch that follows.
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

// `gotoFlow` waits its turn for the one request that starts a flow, but the same limit covers every form POST
// afterwards, and Traefik answers the POST itself so the next form is simply not on the page.
// The unit of retry is the whole flow: a POST Traefik refused never reached Kratos, so nothing was created.
async function throughRateLimit<T>(page: Page, flow: () => Promise<T>): Promise<T> {
  const deadline = Date.now() + 120_000;
  // Two renderings of one 429: Traefik's bare body when the refused request is the form POST, and the app's own "no flow to render" when it is the flow fetch.
  const rateLimited = () =>
    page
      .locator("body")
      .innerText()
      .then(
        (text) =>
          text.trim() === "Too Many Requests" || /Could not start .*\. Please retry\./.test(text),
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

// Wait until the Kratos session cookie is actually set in the context. notOnLogin
// only proves the URL left the login page; a subsequent flow init (e.g. settings)
// can otherwise race ahead of the Set-Cookie and bounce to the return URL.
async function waitForSession(page: Page): Promise<void> {
  await expect
    .poll(async () => (await page.context().cookies()).some((c) => c.name === "ory_kratos_session"), {
      timeout: 15_000,
    })
    .toBe(true);
}

// Neither signal above proves the redirect chain finished: notOnLogin goes true at its start and waitForSession
// lands mid-chain, so a caller that navigates on either races a redirect that wins and cancels the goto.
// Stability rather than a specific URL, so a caller passing return_to does not hang on a URL it changed.
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

// passwordLogin completes first-factor (AAL1) login through the rendered form.
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

// The only path that fires the registration `after` web_hook: admin-API identities skip self-service flows and
// never get a personal org.
// Registration is two-step — traits then credentials — and driving it as one form hangs on a password field that is not there yet.
export async function register(page: Page, email: string, password: string): Promise<void> {
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("registration"), 'input[name="traits.email"]');
    await page.fill('input[name="traits.email"]', email);
    await page.click(submitFor("profile"));

    await page.locator('input[name="password"]').waitFor({ state: "visible", timeout: 20_000 });
    await page.fill('input[name="password"]', password);
    await page.click(submitFor("password"));
    // Kratos re-renders the register form with the message on any failure, including a blocking orgs web_hook, so leaving the form is the success signal.
    await expect(page).not.toHaveURL(/\/auth\/register/, { timeout: 30_000 });
  });
}

// Drives the same two-step form as `register` for the opposite outcome. Returns the rendered text so the caller can pin which rule fired — a test asserting only "rejected" is how a dead breach check hides.
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

// The rejection assertions, split out so the retry above wraps the whole flow.
async function readRejection(page: Page): Promise<string> {
  // Staying on /auth/register is the rejection signal. The message rides the password node, so read the page
  // rather than pinning that markup.
  // Leaving the form means the policy accepted the credential, and the raw diff would read like a routing bug.
  await expect(
    page,
    "password was ACCEPTED — the policy that should have refused it did not fire",
  ).toHaveURL(/\/auth\/register/, { timeout: 30_000 });
  await page.locator('input[name="password"]').waitFor({ state: "visible", timeout: 20_000 });
  return page.locator("body").innerText();
}

// An operator has TOTP enrolled, so this answers the second factor on the same /auth/login flow and ends with an AAL2 session. passwordLogin assumes a password-only identity.
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

  // With a second factor enrolled and required_aal highest_available, Kratos renders the TOTP challenge on the same /auth/login URL. A password-only identity redirects away instead.
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

  // An operator has a second factor, so anything short of aal2 is a failed step-up. A 429 on the aal2
  // continuation renders "Could not start sign-in" instead of the TOTP form, so the prompt never appears and the
  // AAL1 session surfaces much later as a dashboard title reading "Platform".
  await expect(async () => {
    if ((await sessionAal(page)) !== "aal2") {
      await ensureAal2(page, secret);
      await settle(page);
    }
    expect(await sessionAal(page)).toBe("aal2");
  }).toPass({ timeout: 90_000, intervals: [RATE_LIMIT_WAIT_MS] });
}

// sessionAal reads the AAL Kratos itself records for the browser session, which is
// the only authority on whether a step-up landed — the URL after a login says
// nothing about it. Returns null when there is no session at all.
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

// enrolTotp enrols a TOTP second factor via the settings flow, reading the secret
// Kratos generates (rendered as the font-mono text node) and verifying a code.
// Returns the secret so an AAL2 re-login can be driven deterministically.
export async function enrolTotp(page: Page): Promise<string> {
  const secretNode = page.locator("p.font-mono").first();
  // Re-init if the flow ever bounces to the return URL before the form renders.
  await expect(async () => {
    await gotoFlow(page, init("settings"));
    await expect(secretNode).toBeVisible({ timeout: 8_000 });
  }).toPass({ timeout: 40_000 });
  const secret = (await secretNode.innerText()).replace(/\s+/g, "");
  await page.fill('input[name="totp_code"]', await freshTotp(page, secret));
  await page.click(submitFor("totp"));
  // Settings reloads with the factor enrolled; the secret node disappears.
  await expect(secretNode).toBeHidden({ timeout: 20_000 });
  return secret;
}

// Completing TOTP enrolment in a privileged settings flow already elevates the session, so the ?aal=aal2 login usually finds nothing to step up.
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

// Drives the real recovery form, which is what makes the Kratos courier submit a message (ADR-0307).
// `use: code` means the mail carries a six-digit code, and the flow stays open until it is entered.
export async function startRecovery(page: Page, email: string): Promise<void> {
  // Wrapped like every other flow that POSTs: `auth-ratelimit` covers the submit as well as the init, and a refused POST never reached Kratos, so re-running from the init is safe.
  await throughRateLimit(page, async () => {
    await gotoFlow(page, init("recovery"), 'input[name="email"]');
    await page.fill('input[name="email"]', email);
    await page.click(submitFor("code"));
    // Enumeration protection renders the code form identically for an address with no account, so this proves the flow moved and not that anything was sent.
    await page.locator('input[name="code"]').waitFor({ state: "visible", timeout: 30_000 });
  });
}
