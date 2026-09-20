// Browser-side fetcher (ADR-0400), paired with TanStack Query.
"use client";

import createClient, { type Client } from "openapi-fetch";
import { denialMiddleware } from "@/lib/auth/denial";

// Flat API (ADR-0306): every service is reached under the shared /api prefix on
// the same origin. The typed resource path (e.g. /products) selects the endpoint;
// which service serves it is hidden behind the edge, so no service name is passed.
export function createBrowserClient<Paths extends object>(): Client<Paths> {
  // Same denial handling as the server client. On this side the interrupt lands wherever the call was made from, and the panel providers re-throw it during render once for the whole group.
  const client = createClient<Paths>({ baseUrl: "/api" });
  client.use(denialMiddleware);
  return client;
}
