// Self-service cannot grant privileges (ADR-0304): the operator flag lives in
// metadata_public, which only the admin API writes. A registered identity must come
// out carrying no grant at all.
import { expect, test } from "@playwright/test";
import { register } from "../fixtures/kratos";
import { portForward } from "../fixtures/kube";

const KRATOS_ADMIN = "http://127.0.0.1:4434";
const EMAIL = `privilege-${Date.now()}@e2e.localtest.me`;
const PASSWORD = "Tr0ubadour-Fjord-Lantern-9!";

interface Identity {
  id: string;
  traits?: Record<string, unknown>;
  metadata_public?: Record<string, unknown>;
}

test.describe("self-service privilege escalation", () => {
  // Anonymous on purpose: an authenticated visitor is bounced off the registration
  // flow, which is the path under test.
  test.use({ storageState: undefined });

  test.afterAll(async () => {
    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      const res = await fetch(
        `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(EMAIL)}`,
      );
      if (!res.ok) return;
      const list = (await res.json()) as Identity[];
      const hit = list.find((i) => i.traits?.email === EMAIL);
      if (hit) {
        await fetch(`${KRATOS_ADMIN}/admin/identities/${hit.id}`, { method: "DELETE" });
      }
    } finally {
      pf.stop();
    }
  });

  test("a registered identity carries no operator grant @smoke", async ({ browser }) => {
    const anon = await browser.newContext({ ignoreHTTPSErrors: true, storageState: undefined });
    try {
      await register(await anon.newPage(), EMAIL, PASSWORD);
    } finally {
      await anon.close();
    }

    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      const res = await fetch(
        `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(EMAIL)}`,
      );
      expect(res.ok, "the identity must exist in Kratos").toBeTruthy();
      const list = (await res.json()) as Identity[];
      const identity = list.find((i) => i.traits?.email === EMAIL);
      expect(identity, "registered identity must exist").toBeTruthy();

      // The grant is the absence of both: the trait is gone from the schema, and
      // metadata_public is written only by the admin API.
      expect(identity?.traits ?? {}, "traits must not carry an operator grant").not.toHaveProperty(
        "operator",
      );
      expect(
        identity?.metadata_public ?? {},
        "metadata_public must not carry an operator grant from self-service",
      ).not.toHaveProperty("operator");
    } finally {
      pf.stop();
    }
  });
});
