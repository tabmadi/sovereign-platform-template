// One config and one runner, per ADR-0601. The Go and shell preflight runs first as a globalSetup.
import { defineConfig } from "@playwright/test";
import { BASE_URL } from "./fixtures/env";

export default defineConfig({
  testDir: ".",
  // Heavy SPA dashboards and a shared identity store: run serial for a deterministic result.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  // Preflight readiness gate in Go. It separates `infra down` from `app broken` before any browser starts.
  // Skip it with E2E_SKIP_PREFLIGHT=1 when you work against a cluster that you know is healthy.
  globalSetup: "./preflight/preflight.setup.ts",
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: BASE_URL,
    ignoreHTTPSErrors: true, // the local wildcard cert is self-signed
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /fixtures\/auth\.setup\.ts/ },
    { name: "platform", testDir: "platform", dependencies: ["setup"] },
    // Visual regression is its own project. So `--project visual` checks a baseline without a full acceptance run,
    // and a baseline update is a diff in one directory, per ADR-0601.
    { name: "visual", testDir: "visual", dependencies: ["setup"] },
  ],
});
