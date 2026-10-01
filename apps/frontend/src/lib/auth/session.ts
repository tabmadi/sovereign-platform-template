// Resolves the session cookie to an identity on the server, per ADR-0400 and ADR-0304.
import "server-only";

import { headers } from "next/headers";

// The in-cluster Kratos public API, reached east-west by Service DNS and not through the edge.
// The edge would route this back to Oathkeeper, which is the component that asks the question.
const KRATOS_PUBLIC =
  process.env.KRATOS_PUBLIC_URL ?? "http://ory-kratos-public.platform.svc.cluster.local";

export type Session = {
  /** The Kratos identity id. This is the `user:<id>` subject in every authz check. */
  identityId: string;
  /** The session's assurance level, `aal1` or `aal2`, per ADR-0304. */
  aal: string;
};

type WhoamiResponse = {
  identity?: { id?: string };
  authenticator_assurance_level?: string;
};

/**
 * The current session, or null when there is none. Null is a valid answer: an expired cookie is normal, and the caller decides between `unauthorized()` and a public render.
 * A transport failure throws, because an unreachable Kratos must not look like a user who is not signed in.
 */
export async function getSession(): Promise<Session | null> {
  const cookie = (await headers()).get("cookie");
  if (!cookie) {
    return null;
  }
  const res = await fetch(`${KRATOS_PUBLIC}/sessions/whoami`, {
    headers: { cookie },
    // A session check is never cached: it must reflect the request being served, and Next caches server fetches by default.
    cache: "no-store",
  });
  if (res.status === 401 || res.status === 403) {
    return null;
  }
  if (!res.ok) {
    throw new Error(`kratos whoami: ${res.status}`);
  }
  const body = (await res.json()) as WhoamiResponse;
  const identityId = body.identity?.id;
  if (!identityId) {
    return null;
  }
  return {
    identityId,
    aal: body.authenticator_assurance_level ?? "aal1",
  };
}
