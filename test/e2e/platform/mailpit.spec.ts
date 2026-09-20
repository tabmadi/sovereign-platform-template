// The Mailpit viewer dashboard: non-prod only, gated at the ops origin (ADR-0307, ADR-0306).
import { type APIRequestContext, expect, test } from "@playwright/test";
import {
  expectAal1Forbidden,
  expectOperatorAllowed,
  expectUnauthenticatedDenied,
} from "../fixtures/dashboard";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { ADMIN } from "../fixtures/identities";
import { startRecovery } from "../fixtures/kratos";

const MAILPIT = `${opsURL("mailpit")}/`;

test.describe("mailpit ops dashboard", () => {
  test("gated: unauthenticated is denied", async () => {
    await expectUnauthenticatedDenied("mailpit");
  });

  test("gated: AAL1 product session is forbidden", async () => {
    await expectAal1Forbidden("mailpit");
  });

  test("gated: AAL2 operator passes the dashboard:mailpit#view grant", async () => {
    await expectOperatorAllowed("mailpit");
  });

  test.describe("renders behind AAL2", () => {
    test.use({ storageState: OPERATOR_STATE });
    test("the Mailpit SPA paints at the subdomain root", async ({ page }) => {
      await page.goto(MAILPIT);
      await expect(page).not.toHaveURL(/\/auth\/login/);
      // Mailpit mounts its SPA at root and titles the document "Mailpit".
      await expect(page).toHaveTitle(/mailpit/i, { timeout: 30_000 });
    });
  });

  // Mailpit exposes an HTTP API over the same store the UI reads (ADR-0307), which is what lets a test assert delivery. It sits behind the same operator gate as the UI.
  test.describe("holds a readable recovery mail", () => {
    test.use({ storageState: OPERATOR_STATE });

    test("the code in the body matches the code in the subject", async ({ page, browser }) => {
      // Three waits stack and the 60s default covers none: gotoFlow retries for up to 90s under the auth rate limit, then the courier drains its queue on its own schedule.
      test.setTimeout(240_000);

      const recipient = ADMIN.email;
      // Only messages newer than this count. The sink is shared with whoever is
      // using the cluster, so the run neither clears it nor reads a message an
      // earlier run left behind.
      const since = Date.now();

      // Recovery refuses to start for an identity that already has a session, so it is driven in a context with none.
      // storageState is emptied explicitly — a bare newContext() under this `test.use` still arrives holding the session.
      // ignoreHTTPSErrors is restated because the project's `use` block does not reach a hand-made context.
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

      // Kratos puts the code in the subject and the body. Asserting only that a message arrived passes on an empty template, and production keeps no store to show it (ADR-0307).
      const subjectCode = message.Subject.match(/\b(\d{6})\b/)?.[1];
      expect(subjectCode, `no six-digit code in subject: ${message.Subject}`).toBeDefined();

      const detail = await page.request.get(`${opsURL("mailpit")}/api/v1/message/${message.ID}`);
      expect(detail.status()).toBe(200);
      const { Text } = (await detail.json()) as { Text: string };
      expect(Text).toContain(subjectCode);

      // The sender is deliberately NOT asserted. `from_address` is unset, so Kratos
      // sends as its own upstream default rather than as the platform, and pinning
      // that here would make a configuration gap look like a decision.
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

// newestTo returns the most recent message addressed to `address` that arrived at or
// after `since`, or null while none has.
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
