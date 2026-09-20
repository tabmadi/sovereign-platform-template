// The registration to personal-org flow (ADR-0304, ADR-0302): Kratos owns identities, orgs owns the org.
import { expect, test } from "@playwright/test";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { register, registerExpectingRejection } from "../fixtures/kratos";
import { portForward } from "../fixtures/kube";

const KRATOS_ADMIN = "http://127.0.0.1:4434";

const EMAIL = `signup-${Date.now()}@e2e.localtest.me`;

// The personal org is named generically, not by the email, which would leak PII to every member invited later
// (ADR-0301). The registrant's assertable link is the OpenFGA admin tuple, which is dual-write leg 2.
// Local forward port 18080, because the local edge maps host 8080 to the edge.
const PERSONAL_ORG_NAME = "Personal workspace";
const OPENFGA_LOCAL_PORT = Number(process.env.OPENFGA_LOCAL_PORT ?? 18080);
const OPENFGA_TOKEN = process.env.OPENFGA_TOKEN ?? "localdevkey";

// kratosIdFor resolves the Kratos id for a registered email (the authz subject).
async function kratosIdFor(email: string): Promise<string | null> {
  const res = await fetch(
    `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(email)}`,
  );
  if (!res.ok) {
    return null;
  }
  const list = (await res.json()) as Array<{ id: string; traits?: { email?: string } }>;
  return list.find((i) => i.traits?.email === email)?.id ?? null;
}

// adminOrgIds returns the orgs on which `user:<id>` holds `admin` in OpenFGA — the
// ReBAC side of the registration dual-write (model.fga). Assumes a port-forward to
// the OpenFGA HTTP API is already up on OPENFGA_LOCAL_PORT.
async function adminOrgIds(identityId: string): Promise<string[]> {
  const base = `http://127.0.0.1:${OPENFGA_LOCAL_PORT}`;
  const headers = { authorization: `Bearer ${OPENFGA_TOKEN}`, "content-type": "application/json" };
  const stores = (await (await fetch(`${base}/stores`, { headers })).json()) as {
    stores?: { id: string; name: string }[];
  };
  const sid = stores.stores?.find((s) => s.name === "platform")?.id;
  if (!sid) {
    throw new Error("openfga store 'platform' not found — has the seed Job run?");
  }
  const res = await fetch(`${base}/stores/${sid}/list-objects`, {
    method: "POST",
    headers,
    body: JSON.stringify({ type: "org", relation: "admin", user: `user:${identityId}` }),
  });
  if (!res.ok) {
    throw new Error(`openfga list-objects failed: ${res.status} ${await res.text()}`);
  }
  const body = (await res.json()) as { objects?: string[] };
  return (body.objects ?? []).map((o) => o.replace(/^org:/, ""));
}

// Self-service registration enforces the password policy, unlike the admin import path. A policy rejection would fail as "no org appeared" and read as an orgs bug.
const PASSWORD = "Tr0ubadour-Fjord-Lantern-9!";

test.describe("self-service registration", () => {
  // The assertion runs as the operator: the orgs changelist is an ops dashboard.
  test.use({ storageState: OPERATOR_STATE });

  // The identity outlives the org cleanup below, so remove it directly through the
  // admin API — same teardown shape as the createOperator suite in admin.spec.ts.
  test.afterAll(async () => {
    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      const res = await fetch(
        `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(EMAIL)}`,
      );
      if (!res.ok) return;
      const list = (await res.json()) as Array<{ id: string; traits?: { email?: string } }>;
      const hit = list.find((i) => i.traits?.email === EMAIL);
      if (hit) {
        await fetch(`${KRATOS_ADMIN}/admin/identities/${hit.id}`, { method: "DELETE" });
      }
    } finally {
      pf.stop();
    }
  });

  test("registering a new identity creates its personal org @smoke", async ({ browser, page }) => {
    // `storageState: undefined` is load-bearing: newContext() inherits the describe-level `test.use`, and Kratos bounces an already authenticated visitor off the registration flow.
    const anon = await browser.newContext({ ignoreHTTPSErrors: true, storageState: undefined });
    try {
      await register(await anon.newPage(), EMAIL, PASSWORD);
    } finally {
      await anon.close();
    }

    // Resolve the registrant's Kratos id — the authz subject `user:<id>`.
    const kratosPf = await portForward("ory-kratos-admin", 4434, 80);
    let identityId: string | null;
    try {
      identityId = await kratosIdFor(EMAIL);
    } finally {
      kratosPf.stop();
    }
    expect(identityId, "registered identity must exist in Kratos").toBeTruthy();

    // The blocking web_hook only enqueues RegisterUser; the worker runs the two dual-write legs out of band.
    // A timeout means the workflow never completed, which is the regression this guards.
    const fgaPf = await portForward("openfga", OPENFGA_LOCAL_PORT, 8080);
    let orgId = "";
    try {
      await expect(async () => {
        const ids = await adminOrgIds(identityId as string);
        expect(ids).toHaveLength(1);
        orgId = ids[0];
      }).toPass({ timeout: 60_000 });
    } finally {
      fgaPf.stop();
    }

    // Cleaned up through the console: the changelist grid paginates at 20 rows client-side, so a leftover row per run would push new orgs off the first page (ADR-0601).
    await page.goto(`${opsURL("lowdefy")}/orgs_edit?id=${orgId}`);
    const del = page.getByRole("button", { name: "Delete", exact: true });
    await expect(del).toBeVisible({ timeout: 15_000 });
    await del.click();
    await expect(page).toHaveURL(/\/orgs$/, { timeout: 15_000 });
  });
});

// The password policy is Kratos config injected into the chart (ADR-0304); if that injection breaks, Kratos
// falls back to its own defaults and accepts weaker passwords than the ADR claims.
// The breach check is off by default, so this asserts the rule that is always on.
test.describe("password policy", () => {
  // Register anonymously. Explicit, not inherited: this describe is a sibling of
  // the operator-scoped one above, and an authenticated visitor is bounced off the
  // registration flow entirely (see the note on the test above).
  test.use({ storageState: undefined });

  const WEAK_EMAIL = `weak-${Date.now()}@e2e.localtest.me`;

  // 9 chars: under min_password_length (12) and dissimilar to the identifier, so
  // the length rule is the only one that can reject it — which makes the assertion
  // below specific rather than "something said no".
  const WEAK_PASSWORD = "Fjord-9Ln";

  test("a password under the length policy is refused and creates no identity @smoke", async ({
    page,
  }) => {
    const rendered = await registerExpectingRejection(page, WEAK_EMAIL, WEAK_PASSWORD);

    // Pin the REASON, not just the refusal, so this stays green only while the
    // length rule is what fired.
    expect(rendered, "rejection must name the length rule, not another rule").toMatch(
      /at least 12 characters|too short/i,
    );

    // The security assertion proper: no identity exists.
    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      expect(
        await kratosIdFor(WEAK_EMAIL),
        "a password under the length policy must not create an identity",
      ).toBeNull();
    } finally {
      pf.stop();
    }
  });
});
