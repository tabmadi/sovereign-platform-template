// Playwright globalSetup: the Go preflight readiness gate, before any browser starts (ADR-0601).
import { execFileSync } from "node:child_process";

export default function globalSetup(): void {
  if (process.env.E2E_SKIP_PREFLIGHT === "1") {
    console.log("preflight: skipped (E2E_SKIP_PREFLIGHT=1)");
    return;
  }
  // cwd is the test/e2e/ config dir.
  execFileSync("bash", ["preflight/preflight.sh"], { stdio: "inherit" });
}
