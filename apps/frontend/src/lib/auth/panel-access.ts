// The authoritative page gate, per ADR-0700 and ADR-0304.
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
 * Requires the caller to hold `relation` on `object`, or renders the matching access-denial page. The two denials are different facts, per ADR-0400.
 * No session is `unauthorized()`, because signing in fixes it. A session without the grant is `forbidden()` at the denied address, which the user shares.
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
  // An error here means that authz is unreachable, which is not a denial. The throw sends it to `error.tsx`, so a failed check never shows as a refusal.
  // The reader must respond to the two in opposite ways.
  if (error) {
    throw new Error(`authz relation check failed for ${object}`);
  }
  if (!data.allowed) {
    forbidden();
  }
}
