// Self-service cannot grant privileges, per ADR-0304. The requests are what an attacker sends, not what the UI renders.
// The test submits the operator field directly to the Kratos API flows, at registration and in settings.
import { type APIRequestContext, expect, test } from "@playwright/test";
import { BASE_URL } from "../fixtures/env";
import { portForward } from "../fixtures/kube";

const KRATOS_ADMIN = "http://127.0.0.1:4434";
const PASSWORD = "Tr0ubadour-Fjord-Lantern-9!";
const ATTACKER = `escalate-${Date.now()}@e2e.localtest.me`;
const USER = `settings-${Date.now()}@e2e.localtest.me`;

interface Identity {
  id: string;
  traits?: Record<string, unknown>;
  metadata_public?: Record<string, unknown> | null;
}

const flow = async (request: APIRequestContext, kind: string, token?: string): Promise<string> => {
  const res = await request.get(`${BASE_URL}/auth/self-service/${kind}/api`, {
    headers: token ? { "X-Session-Token": token } : {},
  });
  expect(res.ok(), `${kind} flow init`).toBeTruthy();
  return ((await res.json()) as { id: string }).id;
};

const submit = (request: APIRequestContext, kind: string, id: string, data: object, token?: string) =>
  request.post(`${BASE_URL}/auth/self-service/${kind}?flow=${id}`, {
    data,
    headers: token ? { "X-Session-Token": token } : {},
  });

const identities = async (email: string): Promise<Identity[]> => {
  const pf = await portForward("ory-kratos-admin", 4434, 80);
  try {
    const res = await fetch(`${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(email)}`);
    return res.ok ? ((await res.json()) as Identity[]) : [];
  } finally {
    pf.stop();
  }
};

test.describe("self-service privilege escalation", () => {
  test.use({ storageState: undefined });

  test.afterAll(async () => {
    const pf = await portForward("ory-kratos-admin", 4434, 80);
    try {
      for (const email of [ATTACKER, USER]) {
        const res = await fetch(`${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(email)}`);
        for (const hit of res.ok ? ((await res.json()) as Identity[]) : []) {
          await fetch(`${KRATOS_ADMIN}/admin/identities/${hit.id}`, { method: "DELETE" });
        }
      }
    } finally {
      pf.stop();
    }
  });

  test("registration refuses an operator field @smoke", async ({ request }) => {
    const id = await flow(request, "registration");
    const res = await submit(request, "registration", id, {
      method: "password",
      password: PASSWORD,
      traits: { email: ATTACKER, operator: true },
    });
    expect(res.ok(), "a registration carrying operator must be rejected").toBeFalsy();
    expect(await identities(ATTACKER), "no identity may exist for the attacker").toHaveLength(0);
  });

  test("settings refuses an operator field @smoke", async ({ request }) => {
    const reg = await flow(request, "registration");
    const created = await submit(request, "registration", reg, {
      method: "password",
      password: PASSWORD,
      traits: { email: USER },
    });
    expect(created.ok(), "plain registration").toBeTruthy();

    const login = await flow(request, "login");
    const session = await submit(request, "login", login, { method: "password", identifier: USER, password: PASSWORD });
    const token = ((await session.json()) as { session_token?: string }).session_token;
    expect(token, "login yields a session token").toBeTruthy();

    const settings = await flow(request, "settings", token);
    const res = await submit(
      request,
      "settings",
      settings,
      { method: "profile", traits: { email: USER, operator: true } },
      token,
    );
    expect(res.ok(), "a settings update carrying operator must be rejected").toBeFalsy();

    const [identity] = await identities(USER);
    expect(identity, "the user exists").toBeTruthy();
    expect(identity.traits ?? {}).not.toHaveProperty("operator");
    expect(identity.metadata_public ?? {}).not.toHaveProperty("operator");
  });
});
