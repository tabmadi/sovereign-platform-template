// A signed-in session for the load scenarios, per ADR-0304 and ADR-0601. An order belongs to a buyer and their org, so `POST /api/orders` refuses a caller with no session.
// Headers cannot fake this, because the edge strips client-supplied identity headers before forward-auth. So the suite logs in like a browser and sends the session cookie.
// The login runs once in `setup()`, not per iteration: the run does not measure it, and one Kratos login per VU would put the identity plane in the numbers.
import http from "k6/http";

// login drives the Kratos browser login flow through the edge and returns the session cookie value.
// It throws on any failure and never returns empty. k6 stops the run when setup throws. A scenario that ran on 401s would report a healthy p95 for work the platform never did.
export function login(baseURL, email, password) {
  const json = { headers: { Accept: "application/json", "Content-Type": "application/json" } };

  // Kratos mints the flow and answers with its UI descriptor. The CSRF cookie it sets goes into this VU's jar, and the POST below sends it automatically.
  const init = http.get(`${baseURL}/auth/self-service/login/browser`, json);
  if (init.status !== 200) {
    throw new Error(`login: flow init at ${baseURL} returned HTTP ${init.status}`);
  }

  const flow = init.json();
  const action = flow?.ui?.action;
  if (!action) {
    throw new Error("login: flow has no ui.action. Check that the edge routes /auth/self-service");
  }
  // The anti-CSRF token is a hidden node of the same form that a browser submits.
  const csrfNode = (flow.ui.nodes || []).find((n) => n?.attributes?.name === "csrf_token");
  const csrf = csrfNode?.attributes?.value;
  if (!csrf) {
    throw new Error("login: flow has no csrf_token node");
  }

  const res = http.post(
    action,
    JSON.stringify({ method: "password", identifier: email, password, csrf_token: csrf }),
    json,
  );
  if (res.status !== 200) {
    throw new Error(
      `login: ${email} got HTTP ${res.status}. Check that \`mise run auth:seed\` ran against this cluster`,
    );
  }

  const cookie = http.cookieJar().cookiesForURL(baseURL).ory_kratos_session;
  if (!cookie || cookie.length === 0) {
    throw new Error("login: succeeded but set no ory_kratos_session cookie");
  }
  return cookie[0];
}

// requireOrg asserts that the signed-in identity has an organization. The edge builds X-Org-Id from `metadata_public.org_id`, per ADR-0304.
// The orgs RegisterUser workflow writes that field asynchronously, after the identity exists. Before that, every checkout gets 403, and the status check shows 0% with no reason.
// Like `login`, it fails in setup, where the message can name the cause, and does not produce a full run of numbers for work the platform never did.
export function requireOrg(baseURL, session, email) {
  const res = http.get(`${baseURL}/auth/sessions/whoami`, {
    headers: { Accept: "application/json", Cookie: `ory_kratos_session=${session}` },
  });
  if (res.status !== 200) {
    throw new Error(
      `whoami for ${email} returned HTTP ${res.status}. Check that the session is valid`,
    );
  }
  const orgID = res.json()?.identity?.metadata_public?.org_id;
  if (!orgID) {
    throw new Error(
      `${email} has no organization, so every checkout would get 403. The orgs ` +
        "RegisterUser workflow has not set metadata_public.org_id for this identity. " +
        "Provision it again with the `mise run e2e` setup or POST /identity-created on orgs, then retry.",
    );
  }
  return orgID;
}

// authHeaders is what a scenario adds to every request as the buyer. Each VU has its own cookie jar, and setup's jar is not shared with the VUs.
// So the value passes through setup's return value and is sent explicitly.
export function authHeaders(session) {
  return { Cookie: `ory_kratos_session=${session}` };
}
