// Browser observability init on the OpenTelemetry-JS web SDK, per ADR-0500 and ADR-0400.
"use client";

import { getWebInstrumentations, initializeFaro } from "@grafana/faro-web-sdk";
import { TracingInstrumentation } from "@grafana/faro-web-tracing";
import { fingerprint } from "@libs/observability";

const INGEST = "/api/rum";
const FIRST_PARTY_API = /\/api\//;

let initialized = false;

type ExceptionPayload = {
  type?: string;
  value?: string;
  stacktrace?: { frames?: Array<{ filename?: string; function?: string }> };
  context?: Record<string, string>;
};

// Adds the fault identifier to every outgoing exception, per ADR-0503. It is a `beforeSend` hook, because an error reaches Faro from three paths, and a fingerprint at two misses the third.
// It goes in `context`, never in a label, because the value is high-cardinality by design, per ADR-0500.
function withFingerprint<T extends { type: string; payload: unknown }>(item: T): T {
  if (item.type !== "exception") {
    return item;
  }
  const payload = item.payload as ExceptionPayload;
  const stack = (payload.stacktrace?.frames ?? [])
    .map((frame) => `    at ${frame.function ?? "?"} (${frame.filename ?? "?"})`)
    .join("\n");
  payload.context = {
    ...payload.context,
    "error.fingerprint": fingerprint({ name: payload.type, message: payload.value, stack }),
  };
  return item;
}

export function initBrowserObservability(): void {
  if (initialized || typeof window === "undefined") {
    return;
  }
  initialized = true;

  const faro = initializeFaro({
    url: INGEST,
    app: {
      name: "frontend",
      version: process.env.NEXT_PUBLIC_SERVICE_VERSION ?? "dev",
      environment: process.env.NEXT_PUBLIC_DEPLOY_ENV ?? "dev",
    },
    beforeSend: withFingerprint,
    // Off, for a legal reason and not for tuning, per ADR-0400. Faro's `persistent: false` still writes `com.grafana.faro.session` into sessionStorage.
    // That is storage in the user's terminal equipment, so ePrivacy Art. 5(3) covers it. With this off, the SDK touches no web storage.
    sessionTracking: { enabled: false },
    instrumentations: [
      ...getWebInstrumentations(),
      new TracingInstrumentation({
        instrumentationOptions: {
          propagateTraceHeaderCorsUrls: [FIRST_PARTY_API],
        },
      }),
    ],
  });

  // A correlation id for each page, held in a closure. A reload makes a new id, so nothing is stored or read back, per Art. 5(3).
  // `isSampled` is required: Faro's sampler asks the session, and an unset flag sets `traceparent: ...-00` on every API request, which deletes the whole server-side trace.
  // The rate stays in the collector.
  faro.api.setSession({ id: crypto.randomUUID(), attributes: { isSampled: "true" } });
}
