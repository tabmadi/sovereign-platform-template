// The one place where an access denial from the API becomes UI, per ADR-0400 and ADR-0304.
import { forbidden, unauthorized } from "next/navigation";

// Next tags its access-fallback throws with this digest. It is an internal shape. It is named here once, so the coupling is visible
// and pinned to the Next version in package.json. See the authInterrupts note in next.config.mjs.
const ACCESS_FALLBACK_DIGEST = "NEXT_HTTP_ERROR_FALLBACK";

// Raises the matching interrupt for an API status, and returns for any other status.
// It throws, so the caller does not branch on a return value.
export function raiseForAuthDenial(status: number): void {
  if (status === 401) {
    unauthorized();
  }
  if (status === 403) {
    forbidden();
  }
}

// Reports whether this thrown value is one of the interrupts above. The browser side needs it: TanStack Query catches everything that a queryFn throws,
// and an interrupt reaches its boundary only if it is thrown again during render. See the panel providers.
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

// Shared by both fetch clients. It is here and not copied into each client, so the server and the browser always agree on which statuses count.
export const denialMiddleware = {
  onResponse({ response }: { response: Response }) {
    raiseForAuthDenial(response.status);
  },
};
