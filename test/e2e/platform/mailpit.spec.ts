// The Mailpit viewer dashboard. It runs only outside prod and is gated at the ops origin, per ADR-0307 and ADR-0306.
import { type APIRequestContext, expect, test } from "@playwright/test";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { ADMIN } from "../fixtures/identities";
import { startRecovery } from "../fixtures/kratos";

const MAILPIT = `${opsURL("mailpit")}/`;

test.describe("mailpit ops dashboard", () => {
  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the Mailpit SPA paints at the subdomain root", async ({ page }) => {
      await page.goto(MAILPIT);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // Mailpit mounts its SPA at root and sets the document title to `Mailpit`.
      await expect(page).toHaveTitle(/mailpit/i, { timeout: 30_000 });
    });
  });

  // Mailpit exposes an HTTP API over the same store that the UI reads, per ADR-0307. This API lets a test assert delivery. The same operator gate as the UI protects it.
  test.describe("holds a readable recovery mail", () => {
    test.use({ storageState: OPERATOR_STATE });

    test("the code in the body matches the code in the subject", async ({ page, browser }) => {
      // Three waits add up, and the 60s default covers none of them. gotoFlow retries for up to 90s under the auth rate limit, then the courier sends its queue on its own schedule.
      test.setTimeout(240_000);

      const recipient = ADMIN.email;
      // Only messages newer than this count. The sink is shared with anyone who uses the cluster.
      // So the run does not clear it, and it does not read a message from an earlier run.
      const since = Date.now();

      // Recovery does not start for an identity that already has a session, so the test uses a context with no session.
      // storageState is set to empty explicitly: a bare newContext() under this `test.use` still has the session.
      // ignoreHTTPSErrors is set again, because the project's `use` block does not reach a context made by hand.
      const anon = await browser.newContext({
        ignoreHTTPSErrors: true,
        storageState: { cookies: [], origins: [] },
      });
      try {
        await startRecovery(await anon.newPage(), recipient);
      } finally {
        await anon.close();
      }

      let found: SinkMessage | undefined;
      await expect(async () => {
        const message = await newestTo(page.request, recipient, since);
        expect(message, `no message for ${recipient} reached the sink`).not.toBeNull();
        found = message ?? undefined;
      }).toPass({ timeout: 60_000, intervals: [1_000, 2_000, 5_000] });

      const message = found as SinkMessage;
      expect(message.To.map((t) => t.Address)).toContain(recipient);

      // Kratos puts the code in the subject and the body. A check that only a message arrived passes on an empty template, and production keeps no store to show it, per ADR-0307.
      const subjectCode = message.Subject.match(/\b(\d{6})\b/)?.[1];
      expect(subjectCode, `no six-digit code in subject: ${message.Subject}`).toBeDefined();

      const detail = await page.request.get(`${opsURL("mailpit")}/api/v1/message/${message.ID}`);
      expect(detail.status()).toBe(200);
      const { Text } = (await detail.json()) as { Text: string };
      expect(Text).toContain(subjectCode);

      // The sender is NOT asserted, on purpose. `from_address` is unset, so Kratos sends as its own upstream default and not as the platform.
      // An assertion on it here would make a configuration gap look like a decision.
    });
  });
});

type SinkMessage = {
  ID: string;
  Subject: string;
  Created: string;
  From: { Address: string };
  To: Array<{ Address: string }>;
};

// newestTo returns the newest message to `address` that arrived at or after `since`, or null while there is none.
async function newestTo(
  request: APIRequestContext,
  address: string,
  since: number,
): Promise<SinkMessage | null> {
  const query = encodeURIComponent(`to:${address}`);
  const res = await request.get(`${opsURL("mailpit")}/api/v1/search?query=${query}`);
  expect(res.status()).toBe(200);
  const { messages } = (await res.json()) as { messages: SinkMessage[] };
  return (
    messages
      .filter((m) => Date.parse(m.Created) >= since)
      .sort((a, b) => Date.parse(b.Created) - Date.parse(a.Created))[0] ?? null
  );
}
