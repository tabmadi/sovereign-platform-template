// Idempotent bootstrap of the committed test identities, per ADR-0601.
import { IDENTITIES, type TestIdentity } from "./identities";
import { portForward } from "./kube";

const KRATOS_ADMIN = "http://127.0.0.1:4434";
// Local forward port for the orgs service. Its /identity-created webhook is the post-registration process.
// It is cluster-audience with no edge route, so the test reaches it the same way as the admin API.
const ORGS_LOCAL_PORT = Number(process.env.ORGS_LOCAL_PORT ?? 18094);
const SCHEMA_ID = "user_v1";
const OPENFGA_PORT = 8080;
// Local forward port for the OpenFGA HTTP API. It is not 8080: the local cluster maps host 8080 to the edge loadbalancer, Traefik.
// A bind on 8080 here collides with the edge, and requests get a 404 from Traefik instead of OpenFGA.
const OPENFGA_LOCAL_PORT = Number(process.env.OPENFGA_LOCAL_PORT ?? 18080);
// The preshared key of the local and CI `cluster:up full`, from the infra secret openfga-creds. Override it for a deployed target.
const OPENFGA_TOKEN = process.env.OPENFGA_TOKEN ?? "localdevkey";

type KratosIdentity = { id: string; traits: { email: string } };

async function findIdentity(email: string): Promise<string | null> {
  const res = await fetch(
    `${KRATOS_ADMIN}/admin/identities?credentials_identifier=${encodeURIComponent(email)}`,
  );
  if (!res.ok) {
    throw new Error(`kratos admin list failed: ${res.status} ${await res.text()}`);
  }
  const list = (await res.json()) as KratosIdentity[];
  const hit = list.find((i) => i.traits?.email === email);
  return hit?.id ?? null;
}

async function deleteIdentity(id: string): Promise<void> {
  const res = await fetch(`${KRATOS_ADMIN}/admin/identities/${id}`, { method: "DELETE" });
  if (!res.ok && res.status !== 404) {
    throw new Error(`kratos admin delete failed for ${id}: ${res.status} ${await res.text()}`);
  }
}

async function createIdentity(id: TestIdentity): Promise<string> {
  const res = await fetch(`${KRATOS_ADMIN}/admin/identities`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      schema_id: SCHEMA_ID,
      // metadata_public.operator is the coarse ops-gate claim, and it is always enforced, per ADR-0306. group:operator membership feeds only the fine gate.
      traits: { email: id.email },
      metadata_public: { operator: id.operator },
      // Import path: Kratos hashes the password and does not run it through the sign-up policy, HIBP and length.
      // So fixed committed credentials are fine.
      credentials: { password: { config: { password: id.password } } },
      // Verify the address in advance, so login never depends on the SMTP sink.
      verifiable_addresses: [
        { value: id.email, via: "email", verified: true, status: "completed" },
      ],
    }),
  });
  if (!res.ok) {
    throw new Error(`kratos admin create failed for ${id.email}: ${res.status} ${await res.text()}`);
  }
  return ((await res.json()) as KratosIdentity).id;
}

// Kratos cannot import a TOTP credential, so the operator's second factor is enrolled at runtime and needs a known start state. Deleting any earlier identity makes every run deterministic.
async function resetIdentity(id: TestIdentity): Promise<string> {
  const existing = await findIdentity(id.email);
  if (existing) {
    await deleteIdentity(existing);
  }
  return createIdentity(id);
}

const OPENFGA_API = `http://127.0.0.1:${OPENFGA_LOCAL_PORT}`;
const fgaHeaders = { authorization: `Bearer ${OPENFGA_TOKEN}`, "content-type": "application/json" };

// Find the platform store by name, with the same lookup as the services.
async function storeId(): Promise<string> {
  const res = await fetch(`${OPENFGA_API}/stores`, { headers: fgaHeaders });
  if (!res.ok) {
    throw new Error(`openfga list stores failed: ${res.status} ${await res.text()}`);
  }
  const body = (await res.json()) as { stores?: { id: string; name: string }[] };
  const hit = body.stores?.find((s) => s.name === "platform");
  if (!hit) {
    throw new Error("openfga store platform not found. Check that the seed Job ran");
  }
  return hit.id;
}

// Write a tuple. The idempotent `already existed` duplicate error counts as success.
async function writeTuple(sid: string, user: string, relation: string, object: string): Promise<void> {
  const res = await fetch(`${OPENFGA_API}/stores/${sid}/write`, {
    method: "POST",
    headers: fgaHeaders,
    body: JSON.stringify({ writes: { tuple_keys: [{ user, relation, object }] } }),
  });
  if (res.ok) {
    return;
  }
  const text = await res.text();
  if (!text.includes("already existed")) {
    throw new Error(`openfga write failed: ${res.status} ${text}`);
  }
}

// The admin import runs no self-service flow. So the `after` web_hook never fires, and the identity has no personal org and no X-Org-Id, per ADR-0304.
// Calling the webhook does what the registration flow does. The workflow id comes from the identity, so a repeat is a no-op.
async function registerUser(identityId: string, email: string): Promise<void> {
  const res = await fetch(`http://127.0.0.1:${ORGS_LOCAL_PORT}/identity-created`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ identity_id: identityId, email }),
  });
  if (!res.ok) {
    throw new Error(`orgs identity-created failed for ${email}: ${res.status} ${await res.text()}`);
  }
}

// provision creates both identities and writes the operator's group membership.
// It returns the Kratos id of each, so the setup project can match sessions to identities.
export async function provision(): Promise<Record<string, string>> {
  const kratosPf = await portForward("ory-kratos-admin", 4434, 80);
  const ids: Record<string, string> = {};
  try {
    for (const id of IDENTITIES) {
      // A reset identity is created again on each run, for a deterministic state. A stable identity, admin, is created only if missing.
      // So an e2e run never deletes a human's session and enrolled TOTP.
      ids[id.label] = id.reset
        ? await resetIdentity(id)
        : ((await findIdentity(id.email)) ?? (await createIdentity(id)));
    }
  } finally {
    kratosPf.stop();
  }

  const orgsPf = await portForward("orgs-server", ORGS_LOCAL_PORT, 80);
  try {
    for (const id of IDENTITIES) {
      await registerUser(ids[id.label], id.email);
    }
  } finally {
    orgsPf.stop();
  }

  // Operator membership uses each new Kratos id, because the authz subject is `user:<kratos-id>`.
  // Every operator identity gets group:operator, not only the one that the suite logs in as. The write is idempotent.
  const openfgaPf = await portForward("openfga", OPENFGA_LOCAL_PORT, OPENFGA_PORT);
  try {
    const sid = await storeId();
    for (const id of IDENTITIES) {
      if (id.operator) {
        await writeTuple(sid, `user:${ids[id.label]}`, "member", "group:operator");
      }
    }
  } finally {
    openfgaPf.stop();
  }

  return ids;
}
