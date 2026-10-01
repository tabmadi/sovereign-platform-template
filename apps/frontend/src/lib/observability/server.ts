// Server-side logger, per ADR-0500 and ADR-0400: structured JSON to stdout through pino.
import "server-only";

import pino from "pino";

export const log = pino({
  level: process.env.LOG_LEVEL ?? "info",
  base: {
    service: "frontend",
    version: process.env.SERVICE_VERSION ?? "dev",
  },
  // Render JSON, with no pretty-printing in prod. stdout first, per ADR-0500.
  formatters: {
    level: (label) => ({ level: label }),
  },
});
