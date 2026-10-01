// The flow from registration to personal org, per ADR-0304 and ADR-0302. Kratos owns identities, and orgs owns the org.
import { expect, test } from "@playwright/test";
import { OPERATOR_STATE, opsURL } from "../fixtures/env";
import { register, registerExpectingRejection } from "../fixtures/kratos";
import { portForward } from "../fixtures/kube";

const KRATOS_ADMIN = "http://127.0.0.1:4434";

const EMAIL = `signup-${Date.now()}@e2e.localtest.me`;

// The personal org has a generic name, not the email. The email would leak PII to every member invited later, per ADR-0301.
// The registrant's link that a test can assert is the OpenFGA admin tuple, which is dual-write leg 2.
// Local forward port 18080, because the local edge maps host 8080 to the edge.
const PERSONAL_ORG_NAME = "Personal workspace";
const OPENFGA_LOCAL_PORT = Number(process.env.OPENFGA_LOCAL_PORT ?? 18080);
const OPENFGA_TOKEN = process.env.OPENFGA_TOKEN ?? "localdevkey";

// kratosIdFor finds the Kratos id for a registered email. The id is the authz subject.
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

// adminOrgIds returns the orgs on which `user:<id>` holds `admin` in OpenFGA. This is the ReBAC side of the registration dual-write, from model.fga.
// It expects a port-forward to the OpenFGA HTTP API on OPENFGA_LOCAL_PORT.
async function adminOrgIds(identityId: string): Promise<string[]> {
  const base = `http://127.0.0.1:${OPENFGA_LOCAL_PORT}`;
  const headers = { authorization: `Bearer ${OPENFGA_TOKEN}`, "content-type": "application/json" };
  const stores = (await (await fetch(`${base}/stores`, { headers })).json()) as {
    stores?: { id: string; name: string }[];
  };
  const sid = stores.stores?.find((s) => s.name === "platform")?.id;
  if (!sid) {
    throw new Error("openfga store platform not found. Check that the seed Job ran");
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

// Self-service registration enforces the password policy, and the admin import path does not. A policy rejection would fail as a missing org and look like an orgs bug.
const PASSWORD = "Tr0ubadour-Fjord-Lantern-9!";

test.describe("self-service registration", () => {
  // The assertion runs as the operator, because the orgs changelist is an ops dashboard.
  test.use({ storageState: OPERATOR_STATE });

  // The identity outlives the org cleanup below, so the admin API removes it directly.
  // The promotion suite in admin.spec.ts has the same teardown shape.
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
    // `storageState: undefined` is required. newContext() inherits the describe-level `test.use`, and Kratos sends an authenticated visitor away from the registration flow.
    const anon = await browser.newContext({ ignoreHTTPSErrors: true, storageState: undefined });
    try {
      await register(await anon.newPage(), EMAIL, PASSWORD);
    } finally {
      await anon.close();
    }

    // Find the registrant's Kratos id, which is the authz subject `user:<id>`.
    const kratosPf = await portForward("ory-kratos-admin", 4434, 80);
    let identityId: string | null;
    try {
      identityId = await kratosIdFor(EMAIL);
    } finally {
      kratosPf.stop();
    }
    expect(identityId, "registered identity must exist in Kratos").toBeTruthy();

    // The blocking web_hook only enqueues RegisterUser. The worker runs the two dual-write legs out of band.
    // A timeout means that the workflow never completed, and this test guards against that regression.
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

    // Clean up through the console, per ADR-0601. The changelist grid shows 20 rows per page on the client, so one leftover row per run would push new orgs off the first page.
    await page.goto(`${opsURL("lowdefy")}/orgs_edit?id=${orgId}`);
    const del = page.getByRole("button", { name: "Delete", exact: true });
    await expect(del).toBeVisible({ timeout: 15_000 });
    await del.click();
    await expect(page).toHaveURL(/\/orgs$/, { timeout: 15_000 });
  });
});

// The password policy is Kratos config that the chart injects, per ADR-0304. If that injection breaks, Kratos uses its own defaults and accepts weaker passwords than the ADR states.
// The breach check is off by default, so this asserts the rule that is always on.
test.describe("password policy", () => {
  // Register anonymously. This is set explicitly, not inherited, because this describe is a sibling of the operator-scoped one above.
  // Kratos sends an authenticated visitor away from the registration flow, as the note on the test above states.
  test.use({ storageState: undefined });

  const WEAK_EMAIL = `weak-${Date.now()}@e2e.localtest.me`;

  // 9 characters: under min_password_length, which is 12, and not similar to the identifier.
  // So the length rule is the only rule that can reject it, and the assertion below is specific.
  const WEAK_PASSWORD = "Fjord-9Ln";

  test("a password under the length policy is refused and creates no identity @smoke", async ({
    page,
  }) => {
    const rendered = await registerExpectingRejection(page, WEAK_EMAIL, WEAK_PASSWORD);

    // Check the reason, not only the refusal. So this passes only while the length rule is the rule that fired.
    expect(rendered, "rejection must name the length rule, not another rule").toMatch(
      /at least 12 characters|too short/i,
    );

    // The main security assertion: no identity exists.
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
