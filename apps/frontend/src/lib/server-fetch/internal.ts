// East-west fetcher for cluster-audience services, per ADR-0303 and ADR-0700.
import "server-only";

import createClient, { type Client } from "openapi-fetch";

/**
 * A client for one internal service, addressed by its `<SERVICE>_URL` variable. Services use the same convention to reach each other.
 * A missing variable throws and has no default. Every default is a wrong guess that fails later, at the first request, as a DNS error that nobody links to a missing value.
 */
export function createInternalClient<Paths extends object>(envVar: string): Client<Paths> {
  const baseUrl = process.env[envVar];
  if (!baseUrl) {
    throw new Error(`${envVar} is not set. An internal service cannot be reached without it`);
  }
  return createClient<Paths>({ baseUrl });
}
