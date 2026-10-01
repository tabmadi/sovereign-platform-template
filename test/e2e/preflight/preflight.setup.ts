// Playwright globalSetup: the Go preflight readiness gate runs before any browser starts, per ADR-0601.
import { execFileSync } from "node:child_process";

export default function globalSetup(): void {
  if (process.env.E2E_SKIP_PREFLIGHT === "1") {
    console.log("preflight: skipped, E2E_SKIP_PREFLIGHT=1");
    return;
  }
  execFileSync("bash", ["preflight/preflight.sh"], { stdio: "inherit" });
}
