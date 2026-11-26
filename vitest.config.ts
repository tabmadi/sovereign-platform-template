import { defineConfig } from "vitest/config";

// The tests of the shared TypeScript libraries and the admin console, on Node.js with two workers, per ADR-0110.
export default defineConfig({
  test: {
    include: ["libs/ts/**/*.test.ts", "apps/admin/src/**/*.test.ts"],
    maxWorkers: 2,
  },
});
