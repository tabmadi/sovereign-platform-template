# syntax=docker/dockerfile:1.7
# The build context is this directory, apps/admin. It does not use the repo-root .dockerignore of the Go service images, which excludes apps/.

# Lowdefy 5 needs Node and pnpm to build, so this image is Node-based, unlike the Go and bun runtime images. It is one of the two Node exceptions that ADR-0100 allows, and the only one that ships as an image.
# No repo runtime code is Node. Lowdefy is a third-party app, so upstream chooses the runtime. bun cannot replace it at build: the CLI stops unless pnpm is on PATH.
# The last stage runs the standalone server of Lowdefy's Next build, which upstream targets at Node.
ARG NODE_VERSION=22
ARG LOWDEFY_VERSION=5.4.0
ARG PNPM_VERSION=10.18.2
# Two stages. The build runs as root, and the last stage takes its tree with `COPY --chown`.
# A `chown -R` in the same stage writes every file again into a second layer, which doubles the image and its SBOM scan.
FROM node:${NODE_VERSION}-alpine AS build
ARG LOWDEFY_VERSION
WORKDIR /app
# Lowdefy needs pnpm at BUILD and at START. `lowdefy start` does not run without pnpm on PATH, per its checkPnpmIsInstalled, and then spawns it.

# Install pnpm globally, not with `corepack enable`. corepack installs only a SHIM, and the real pnpm downloads on first use into the user's own cache.
# That works as root during the build, and fails at start as `node`, per ADR-0200: the cache is not writable, and default-deny egress drops the registry fetch.
# `npm install -g` puts the real pnpm in /usr/local/lib/node_modules at build time, and every user can read it.

# pnpm 10+ fails with ERR_PNPM_IGNORED_BUILDS when a dependency's build script is blocked. The Lowdefy server's deps, sharp and @sentry/cli, need theirs, so allow them.

# The network settings are for the install that `lowdefy build` runs below through its installServer. It is the longest fetch in this image.
# Behind a slow proxy, one stalled request fails the whole build with only `Dependency installation failed`. Measured: failures at 242s, 340s, and 390s, and 442s to finish.
# pnpm's defaults give one retry and a 60s limit. These give five retries and ten minutes, and lower concurrency gives the proxy fewer parallel TLS sessions, like the cluster scripts.
ARG PNPM_VERSION
RUN npm install -g pnpm@${PNPM_VERSION} \
  && pnpm config set dangerously-allow-all-builds true \
  && pnpm config set fetch-retries 5 \
  && pnpm config set fetch-retry-mintimeout 10000 \
  && pnpm config set fetch-retry-maxtimeout 120000 \
  && pnpm config set fetch-timeout 600000 \
  && pnpm config set network-concurrency 4
# Lowdefy's own `@lowdefy/server` fetch is a raw axios GET to registry.npmjs.org, and it often gets `socket hang up` or 400 through this project's egress proxy. npm's fetcher, pacote, does not.
# So `npm pack` fills the server directory first, and `lowdefy build` skips its own fetch.
# lowdefy's getServer.js skips the fetch when the .lowdefy/server/package.json name and version already match.
# This runs before `COPY . .`, so a change to the pages does not fetch the CLI and the server again.
RUN npm install -g lowdefy@${LOWDEFY_VERSION} \
  && mkdir -p .lowdefy/server \
  && npm pack "@lowdefy/server@${LOWDEFY_VERSION}" --pack-destination /tmp \
  && tar xzf "/tmp/lowdefy-server-${LOWDEFY_VERSION}.tgz" --strip-components=1 -C .lowdefy/server \
  && rm "/tmp/lowdefy-server-${LOWDEFY_VERSION}.tgz"
# The server's dependencies before `COPY . .`, so a page change reuses this layer. `lowdefy build` then finds them and only checks them.
# The store is a cache mount, so a new server version fetches only the packages that changed.
RUN --mount=type=cache,target=/root/.local/share/pnpm/store cd .lowdefy/server && pnpm install
COPY . .
# Next's standalone output: a server.js with only the files it imports. The last stage then ships no CLI, no pnpm, and no full node_modules.
ENV LOWDEFY_BUILD_OUTPUT_STANDALONE=1
RUN --mount=type=cache,target=/root/.local/share/pnpm/store lowdefy build

FROM node:${NODE_VERSION}-alpine
# Build identity, per ADR-0103: the commit SHA as the standard OCI revision label, so the image reports what was built.
# The frontend takes the same SERVICE_VERSION build arg, so one apps job builds both.
ARG SERVICE_VERSION=dev
LABEL org.opencontainers.image.revision="${SERVICE_VERSION}"
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
# Run as the `node` user, uid 1000 in the base image, not root. The `restricted` level of the target namespace requires this, per ADR-0200.
# The copies create /app with that owner. A WORKDIR before them would create /app as root.
COPY --from=build --chown=node:node /app/.lowdefy/server/.next/standalone /app
COPY --from=build --chown=node:node /app/.lowdefy/server/.next/static /app/.next/static
COPY --from=build --chown=node:node /app/.lowdefy/server/public /app/public
WORKDIR /app
EXPOSE 3000
USER node
# The standalone server serves the built app on :3000. The edge enforces auth, per ADR-0401, and this process trusts the forwarded X-User-Email header.
CMD ["node", "server.js"]
