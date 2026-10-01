// Server-only fetcher around openapi-fetch, for server components and route handlers, per ADR-0400.
import "server-only";

import { headers } from "next/headers";
import createClient, { type Client } from "openapi-fetch";
import { denialMiddleware } from "@/lib/auth/denial";

// Where this process dials the edge: a host `next dev` uses the mapped port, and an in-cluster pod uses 443.
// Both carry the env host, because the /api IngressRoutes match on it and Oathkeeper injects identity there, per ADR-0305.
// No default: every candidate is a wrong guess, and the client controls the Host header.
const API_BASE = process.env.EDGE_INTERNAL_ORIGIN ?? process.env.EDGE_PUBLIC_ORIGIN;

// Flat API, per ADR-0306: the typed resource path selects the endpoint. The prefix cannot be relative, because a server-side fetch has no document to resolve against.
export async function createServerClient<Paths extends object>(): Promise<Client<Paths>> {
  if (!API_BASE) {
    throw new Error(
      "No edge origin: server components fetch through the edge and need its origin. " +
        "Set EDGE_PUBLIC_ORIGIN (e.g. https://dev.localtest.me:8443), and " +
        "EDGE_INTERNAL_ORIGIN too when running in-cluster (e.g. https://dev.localtest.me). " +
        "Locally, start the dev server with `mise run dev:frontend`; in a deployed env " +
        "set them in infra/gitops/services/<env>/values/frontend.yaml.",
    );
  }

  const h = await headers();
  const cookie = h.get("cookie") ?? "";
  const traceparent = h.get("traceparent") ?? "";

  const client = createClient<Paths>({
    baseUrl: `${API_BASE}/api`,
    headers: {
      ...(cookie && { cookie }),
      ...(traceparent && { traceparent }),
    },
  });

  // This is on the client and not in each caller. openapi-fetch reports a denial as an `{ error }` value.
  // So a page that checks only `data` renders an empty table where it must show that the user has no access.
  // A route that handles a denial itself can `eject` it, on purpose and visibly in review.
  client.use(denialMiddleware);
  return client;
}
