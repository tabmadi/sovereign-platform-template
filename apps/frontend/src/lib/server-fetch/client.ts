// Browser-side fetcher, used with TanStack Query, per ADR-0400.
"use client";

import createClient, { type Client } from "openapi-fetch";
import { denialMiddleware } from "@/lib/auth/denial";

// Flat API, per ADR-0306: every service is under the shared /api prefix on the same origin. The typed resource path, for example /products, selects the endpoint.
// The edge hides which service serves it, so no service name is passed.
export function createBrowserClient<Paths extends object>(): Client<Paths> {
  // The same denial handling as the server client. Here the interrupt arrives where the call was made, and the panel providers throw it again during render, once for the whole group.
  const client = createClient<Paths>({ baseUrl: "/api" });
  client.use(denialMiddleware);
  return client;
}
