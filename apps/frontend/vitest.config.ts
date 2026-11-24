import { defineConfig } from "vitest/config";

// The frontend tests on Node.js with two workers, per ADR-0110, and the coverage of scripts/test-frontend.sh.
export default defineConfig({
  resolve: {
    alias: { "@": new URL("./src", import.meta.url).pathname },
  },
  oxc: { jsx: { runtime: "automatic" } },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
    setupFiles: ["./src/test/setup.ts"],
    maxWorkers: 2,
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov"],
      reportsDirectory: "coverage",
      // Vendored shadcn/ui source and the test harness are not first-party product code, per ADR-0400.
      exclude: ["src/components/ui/**", "src/test/**", "**/*.test.{ts,tsx}"],
    },
  },
});
