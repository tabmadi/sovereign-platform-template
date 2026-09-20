// OpenFeature wiring (ADR-0400). Day one runs the NoopProvider, so calls are inert until a provider is set.
import { type Client, OpenFeature } from "@openfeature/web-sdk";

let client: Client | undefined;

export function flagsClient(): Client {
  if (!client) {
    // NoopProvider is the default when no provider is registered.
    client = OpenFeature.getClient();
  }
  return client;
}
