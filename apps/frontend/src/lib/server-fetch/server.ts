// Server-only fetcher (ADR-0400) wrapping openapi-fetch, for server components and route handlers.
import "server-only";

import { headers } from "next/headers";
import createClient, { type Client } from "openapi-fetch";
import { denialMiddleware } from "@/lib/auth/denial";

// Where this process dials the edge: a host `next dev` uses the mapped port, an in-cluster pod uses 443.
// Both carry the env host, because the /api IngressRoutes match on it and Oathkeeper injects identity there
// (ADR-0305). No default: every candidate is a wrong guess, and the Host header is client-controlled.
const API_BASE = process.env.EDGE_INTERNAL_ORIGIN ?? process.env.EDGE_PUBLIC_ORIGIN;

// Flat API (ADR-0306): the typed resource path selects the endpoint. The prefix cannot be relative — a server-side fetch has no document to resolve against.
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

  // Attached to the client, not left to each caller: openapi-fetch reports a denial as an `{ error }` value, so a
  // page that only checks `data` renders an empty table where it should have said "you do not have access".
  // A route that needs to handle a denial itself can `eject` it, deliberately and visibly in review.
  client.use(denialMiddleware);
  return client;
}
