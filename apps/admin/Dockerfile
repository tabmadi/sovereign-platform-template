# syntax=docker/dockerfile:1.29
# The admin console, per ADR-0401. Bun installs it from the root lockfile, and Node.js builds and runs it, per ADR-0110.
ARG NODE_VERSION=26.13.1
ARG BUN_VERSION=1.4.5

FROM oven/bun:${BUN_VERSION}-alpine AS bun

FROM node:${NODE_VERSION}-alpine AS build
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
WORKDIR /app
COPY package.json bun.lock bunfig.toml ./
# Every workspace member's manifest, because `bun install` resolves the workspace list before it installs anything.
# The frontend Dockerfile holds the same list. A new member needs a line in both.
COPY apps/admin/package.json apps/admin/
COPY apps/frontend/package.json apps/frontend/
COPY libs/ts/id/package.json libs/ts/id/
COPY libs/ts/money/package.json libs/ts/money/
COPY libs/ts/observability/package.json libs/ts/observability/
COPY libs/ts/schemas/package.json libs/ts/schemas/
COPY libs/ts/sdks/ libs/ts/sdks/
COPY test/e2e/package.json test/e2e/
# The filter installs only the packages of the console.
RUN --mount=type=cache,target=/root/.bun bun install --frozen-lockfile --filter=admin
COPY apps/admin/ apps/admin/
ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=$SERVICE_VERSION NEXT_TELEMETRY_DISABLED=1
RUN --mount=type=cache,target=/app/apps/admin/.next/cache cd apps/admin && node --run build

FROM node:${NODE_VERSION}-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build /app/apps/admin/.next/standalone ./
COPY --from=build /app/apps/admin/.next/static ./apps/admin/.next/static
# `node` is the user of the node image, uid 1000. The chart runs as the same user, and the server writes nothing under /app.
USER node
EXPOSE 3000
CMD ["node", "apps/admin/server.js"]
