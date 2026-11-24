import { defineConfig } from "vitest/config";

// The tests of the shared TypeScript libraries, on Node.js with two workers, per ADR-0110.
export default defineConfig({
  test: {
    include: ["libs/ts/**/*.test.ts"],
    maxWorkers: 2,
  },
});
