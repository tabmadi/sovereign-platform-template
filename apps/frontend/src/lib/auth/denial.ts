// The one place an access denial from the API becomes UI (ADR-0400, ADR-0304).
import { forbidden, unauthorized } from "next/navigation";

// Next tags its access-fallback throws with this digest. It is an internal shape,
// named here once so the coupling is visible and pinned to the Next version in
// package.json — see the authInterrupts note in next.config.mjs.
const ACCESS_FALLBACK_DIGEST = "NEXT_HTTP_ERROR_FALLBACK";

// Raises the matching interrupt for an API status, and returns for anything else.
// Throws — the caller does not branch on a return value.
export function raiseForAuthDenial(status: number): void {
  if (status === 401) {
    unauthorized();
  }
  if (status === 403) {
    forbidden();
  }
}

// Is this thrown value one of the interrupts above? Needed on the browser side:
// TanStack Query catches everything a queryFn throws, and an interrupt only
// reaches its boundary if it is re-thrown during render — see the panel providers.
export function isAuthDenial(error: unknown): boolean {
  if (typeof error !== "object" || error === null || !("digest" in error)) {
    return false;
  }
  const { digest } = error as { digest: unknown };
  if (typeof digest !== "string") {
    return false;
  }
  const [prefix, status] = digest.split(";");
  return prefix === ACCESS_FALLBACK_DIGEST && (status === "401" || status === "403");
}

// Shared by both fetch clients. Kept here rather than duplicated per client so the
// server and the browser cannot drift on which statuses count.
export const denialMiddleware = {
  onResponse({ response }: { response: Response }) {
    raiseForAuthDenial(response.status);
  },
};
