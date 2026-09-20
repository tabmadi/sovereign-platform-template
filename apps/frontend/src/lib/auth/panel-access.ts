// The authoritative page gate (ADR-0700, ADR-0304).
import "server-only";

import { forbidden, unauthorized } from "next/navigation";
import { getSession } from "@/lib/auth/session";
import { createInternalClient } from "@/lib/server-fetch/internal";

type AuthzPaths = {
  "/authorize/relation": {
    post: {
      requestBody: {
        content: { "application/json": { subject: string; relation: string; object: string } };
      };
      responses: { 200: { content: { "application/json": { allowed: boolean } } } };
    };
  };
};

/**
 * Requires the caller to hold `relation` on `object`, or renders the matching access-denial page.
 * The two denials are different facts (ADR-0400): no session is `unauthorized()` because signing in is the
 * remedy, and a session without the grant is `forbidden()` at the denied address, which is what the user shares.
 */
export async function requireRelation(relation: string, object: string): Promise<void> {
  const session = await getSession();
  if (session === null) {
    unauthorized();
  }

  const authz = createInternalClient<AuthzPaths>("AUTHZ_URL");
  const { data, error } = await authz.POST("/authorize/relation", {
    body: { subject: `user:${session.identityId}`, relation, object },
  });
  // An error here is authz being unreachable, which is not a denial. Throwing
  // sends it to `error.tsx`, so "we could not ask" never renders as "you may not"
  // — the two need opposite responses from the reader.
  if (error) {
    throw new Error(`authz relation check failed for ${object}`);
  }
  if (!data.allowed) {
    forbidden();
  }
}
