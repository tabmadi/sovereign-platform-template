// Browser observability init (ADR-0500, ADR-0400), on the OpenTelemetry-JS web SDK.
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

// Attaches the fault identifier to every exception on its way out (ADR-0503). A `beforeSend` hook, because an
// error reaches Faro from three paths and a fingerprint added at two under-reports the third.
// It goes in `context`, never a label: the value is high-cardinality by construction (ADR-0500).
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
    // Off, and a legal position rather than a tuning choice (ADR-0400). Faro's `persistent: false` still writes
    // `com.grafana.faro.session` into sessionStorage, which is storage in the user's terminal equipment and so
    // inside ePrivacy Art. 5(3). With this off the SDK touches no web storage at all.
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

  // A per-page correlation id held in a closure: a reload is a new id, so nothing is stored and nothing is read
  // back (Art. 5(3)). `isSampled` is not decoration — Faro's sampler asks the session, and an unset flag stamps
  // `traceparent: …-00` on every API request, deleting the whole server-side trace. The rate stays in the collector.
  faro.api.setSession({ id: crypto.randomUUID(), attributes: { isSampled: "true" } });
}
