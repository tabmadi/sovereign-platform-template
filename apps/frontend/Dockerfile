# syntax=docker/dockerfile:1.7
# Bun is the only JS runtime in this image: install, build, and the production server.js all run under Bun.
# Next's standalone output officially targets Node, but Bun runs it, and without Node the platform has one runtime, per ADR-0000 §"one way to do things".
ARG BUN_VERSION=1.4.2

FROM oven/bun:${BUN_VERSION}-alpine AS deps
WORKDIR /app
COPY package.json bun.lock ./
# Every workspace member's manifest, because `bun install` resolves the workspace list before it installs anything.
# A member in the root package.json that is not in the build context fails the install with `Workspace not found`.
# A new member needs a line here: the root list and this stage are one decision.
COPY apps/frontend/package.json apps/frontend/
COPY libs/ts/id/package.json libs/ts/id/
COPY libs/ts/money/package.json libs/ts/money/
COPY libs/ts/observability/package.json libs/ts/observability/
COPY libs/ts/schemas/package.json libs/ts/schemas/
# The generated SDKs are a GLOB member, `libs/ts/sdks/*`, and are committed like every generated artefact. So bun resolves each one and needs its manifest here.
# A list cannot name them, because each new service brings a new SDK. Copying the tree misses the install cache when an SDK changes.
# That is the cheaper failure. The other is `@sdks/<name>@workspace:* failed to resolve`, minutes into an image build.
COPY libs/ts/sdks/ libs/ts/sdks/
RUN --mount=type=cache,target=/root/.bun bun install --frozen-lockfile

FROM oven/bun:${BUN_VERSION}-alpine AS build
WORKDIR /app
# BOTH trees. In a Bun workspace, a member's executables go into its own node_modules/.bin, not the root's. With only /app/node_modules, the build fails with `next: not found`.
# The build context excludes node_modules, per Dockerfile.dockerignore, so this stage is their only source.
# This also stops a developer's host install from hiding the omission locally while CI builds from a clean checkout.
COPY --from=deps /app/node_modules /app/node_modules
COPY --from=deps /app/apps/frontend/node_modules /app/apps/frontend/node_modules
COPY . .
# Build identity in the bundle, per ADR-0103: next.config inlines NEXT_PUBLIC_SERVICE_VERSION from SERVICE_VERSION at build.
# So the shipped JS and the X-App-Version response header both report the git SHA or release.
ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=$SERVICE_VERSION
# Optional, and EMPTY by default on purpose. `output: "standalone"` freezes next.config into server.js, so this arg bakes the server-action CSRF allowlist and one env's host into the image.
# That breaks the build-once, promote-by-digest flow, per ADR-0103. If it is unset, the allowlist is empty, and the check uses Origin == Host or X-Forwarded-Host.
# ADR-0306's same-origin layout already meets that check. Pass it only for a build that you pin to one env on purpose.

# The name must be EDGE_PUBLIC_ORIGIN, which next.config.mjs reads. If a build arg does not match that variable, nothing reports it, and the allowlist stays empty.
# The RUNTIME origins for server component fetches are separate. They come from the pod env, in infra/gitops/services/<env>/values/frontend.yaml.
ARG EDGE_PUBLIC_ORIGIN=
ENV EDGE_PUBLIC_ORIGIN=$EDGE_PUBLIC_ORIGIN
RUN cd apps/frontend && bun run build

FROM oven/bun:${BUN_VERSION}-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/apps/frontend/.next/standalone ./
COPY --from=build /app/apps/frontend/.next/static    ./apps/frontend/.next/static
COPY --from=build /app/apps/frontend/public          ./apps/frontend/public
# The image declares its own non-root user, and does not leave it to the chart. The service chart sets runAsUser 65532, so runtime does not change.
# But an image that depends only on its manifest is one `docker run` away from root, and the scanner reports it, per ci:scan misconfig DS-0002.
# `bun` is the user of the oven/bun image, uid 1000. The server serves prebuilt output and writes nothing under /app.
USER bun
EXPOSE 3000
CMD ["bun", "apps/frontend/server.js"]
