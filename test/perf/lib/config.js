// Shared configuration for every k6 scenario, per ADR-0601. It holds the target, the load profiles, and options(), so a scenario file holds only request logic.
// This runs on k6's embedded JS engine, Sobek, NOT Node. perf/ has no npm, no package.json, and no node_modules, and must never have one.
// That boundary keeps ADR-0601's Node exception limited to e2e/.

// The target does not depend on a host, like the e2e suite in e2e/fixtures/env.ts. Set PERF_HOST to target a deployed environment.
// The default is only the local edge. A load run must never move onto a shared environment because someone forgot a flag, per ADR-0601.
export const HOST = __ENV.PERF_HOST || "dev.localtest.me:8443";
export const BASE_URL = `https://${HOST}`;
// Flat resource namespace behind the gateway, per ADR-0306. Scenarios call this and not a port-forwarded pod,
// so Traefik and the Oathkeeper forward-auth hop are inside the measurement, per ADR-0305 and ADR-0601.
export const API = `${BASE_URL}/api`;

// Everything that this suite writes has this prefix, so a later cleanup can find and remove seeded and load-generated rows.
export const PERF_PREFIX = "perf-";

// The buyer for the write scenarios. Checkout needs a signed-in caller with an org, per ADR-0304. This is the committed product-user identity from `mise run auth:seed`.
// The credentials are a copy of test/e2e/fixtures/identities.ts, because this island runs on k6's engine and cannot read TypeScript, per ADR-0601.
// If the copy drifts, `setup()` fails with the login error, so the drift is visible.
export const PERF_USER = {
  email: __ENV.PERF_USER_EMAIL || "user@e2e.localtest.me",
  password: __ENV.PERF_USER_PASSWORD || "Pr0duct-e2e-Sessi0n!",
};

// `vus` is the profile's main concurrency. A scenario scales it by its own weight: a checkout is much heavier than a product list, so it gets fewer VUs.
// PERF_VUS overrides the peak of any profile. stages are k6 ramping-vus stages: [{ duration, target }, ...].
const PROFILES = {
  // Proves that the script and the target are connected. It is cheap enough for the lane of each PR.
  smoke: { vus: 1, stages: (v) => [{ duration: "10s", target: v }] },

  // The steady baseline. Nightly runs track this number over time, so its shape must stay stable. A change breaks the history.
  load: {
    vus: 20,
    stages: (v) => [
      { duration: "30s", target: v },
      { duration: "2m", target: v },
      { duration: "30s", target: 0 },
    ],
  },

  // Ramp past the knee. The thresholds are EXPECTED to break here. The output of a stress run is the step where they broke, not a pass or fail.
  stress: {
    vus: 20,
    stages: (v) => [
      { duration: "30s", target: v },
      { duration: "1m", target: v * 2 },
      { duration: "1m", target: v * 4 },
      { duration: "1m", target: v * 8 },
      { duration: "30s", target: 0 },
    ],
  },

  // Sustained load for leak detection: memory that rises while throughput is flat.
  soak: {
    vus: 10,
    stages: (v) => [
      { duration: "1m", target: v },
      { duration: "30m", target: v },
      { duration: "1m", target: 0 },
    ],
  },
};

export const PROFILE = __ENV.PERF_PROFILE || "smoke";

// ADR-0500 forbids high-cardinality metric labels, and k6's default system tags break that rule on a Prometheus that every service shares.
// This is an ALLOW-LIST: a system tag not named here is not emitted. The comments in the array name each omission and its reason.
const SYSTEM_TAGS = [
  // Omitted: url and name, the full request URL. It makes one series per product id, thousands per stress run, and they stay until TSDB retention.
  // The `endpoint` tag on each request carries the route template, which is what a dashboard groups by.
  // Omitted: error, the free-text Go error string, which has no bound. `error_code` is the enumerated k6 equivalent and stays.
  // Omitted: scenario, which k6 sets to the executor name. It would collide with the run-level `scenario` tag in options() below.
  "proto",
  "status",
  "method",
  "group",
  "check",
  "error_code",
  "expected_response",
];

// options builds the k6 `options` export. `scenario` is this file's name, and it tags every metric so the two runs stay separate in Prometheus.
// `weight` multiplies the profile's VU count: 1 is the profile's number, and 0.25 is a quarter of it, for heavy paths.
// `thresholds` are budgets, not SLOs, per ADR-0601. A load run pushes past the SLO on purpose, so the SLO would make every run fail.
export function options(scenario, weight, thresholds) {
  const profile = PROFILES[PROFILE];
  if (!profile) {
    throw new Error(
      `unknown PERF_PROFILE ${PROFILE}, expected one of: ${Object.keys(PROFILES).join(", ")}`,
    );
  }
  const peak = Math.max(1, Math.round((Number(__ENV.PERF_VUS) || profile.vus) * weight));
  const stages = profile.stages(peak);

  return {
    stages,
    // The local edge serves the local wildcard cert, which is self-signed. playwright.config.ts sets ignoreHTTPSErrors for the same reason.
    insecureSkipTLSVerify: true,
    // Thresholds set the process exit code, so a run is a CI gate without a wrapper script.
    // `abortOnFail` is NOT set, on purpose: the run keeps the full curve after a budget fails, most of all under `stress`.
    thresholds,
    // Response bodies are read, so the timing is honest, but not retained. After a few thousand iterations, the product list alone
    // would fill the generator's memory and make the generator the bottleneck, not the platform.
    discardResponseBodies: false,
    // Run-level tags apply to EVERY metric, including the custom Trends, which per-request tags cannot reach.
    // `scenario` separates browse series from checkout series in Prometheus. Both export as service.name=k6, so without it the runs look the same.
    tags: { profile: PROFILE, scenario },
    userAgent: `k6-perf/${PROFILE}`,
    systemTags: SYSTEM_TAGS,
  };
}

// summaryTrailer prints from every scenario's teardown(), so a captured run always carries the caveat.
// A generator on the same host competes with the cluster for CPU, so the numbers are relative regression signals, not capacity figures, per ADR-0601.
export function summaryTrailer() {
  return [
    "",
    `  target:  ${BASE_URL}`,
    `  profile: ${PROFILE}`,
    "  note:    the generator runs on the host and shares CPU with the kind node.",
    "           Read these numbers as a regression signal, not as an absolute capacity figure.",
    "",
  ].join("\n");
}
