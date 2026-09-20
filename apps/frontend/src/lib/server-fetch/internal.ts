// East-west fetcher for cluster-audience services (ADR-0303, ADR-0700).
import "server-only";

import createClient, { type Client } from "openapi-fetch";

/**
 * A client for one internal service, addressed by its `<SERVICE>_URL` variable — the same convention services
 * use to reach each other. A missing variable throws rather than defaulting: every candidate default is a wrong
 * guess that fails later, at the first request, as a DNS error nobody connects to a missing value.
 */
export function createInternalClient<Paths extends object>(envVar: string): Client<Paths> {
  const baseUrl = process.env[envVar];
  if (!baseUrl) {
    throw new Error(`${envVar} is not set — an internal service cannot be reached without it`);
  }
  return createClient<Paths>({ baseUrl });
}
