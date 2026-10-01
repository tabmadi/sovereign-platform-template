// OpenFeature wiring, per ADR-0400. The NoopProvider runs until a provider is set, so calls have no effect.
import { type Client, OpenFeature } from "@openfeature/web-sdk";

let client: Client | undefined;

export function flagsClient(): Client {
  if (!client) {
    client = OpenFeature.getClient();
  }
  return client;
}
