// Next.js config, per ADR-0400. The Bun-only Dockerfile needs standalone output.
// `@libs/id`, the identifier codec that both languages share, per ADR-0003, is outside the app and ships as TypeScript source with no build step. So Next transpiles it like app code.

// Server Actions CSRF allowlist, per ADR-0305 and ADR-0400. It comes from the one edge origin that the BROWSER uses, EDGE_PUBLIC_ORIGIN, never from the internal origin that a pod dials.
// The internal origin has a different port in-cluster and would allow the wrong host. src/lib/server-fetch/server.ts shows the split.
// Next compares the list with `new URL(origin).host`, which INCLUDES the port. So this uses `.host`: a `dev.localtest.me` entry never matches `https://dev.localtest.me:8443`.

// Next reads this list only when Origin ≠ Host or X-Forwarded-Host. ADR-0306 puts `/` and `/api` on the same origin, so this is defence in depth.
// It is fixed at BUILD time: `output: "standalone"` freezes this config into server.js. An image has an entry only if the build passed EDGE_PUBLIC_ORIGIN.
// That pins the image to one env host and breaks the build-once, promote-by-digest flow in ADR-0103. Leave it unset in CI builds.
import createNextIntlPlugin from "next-intl/plugin";

// The plugin points next-intl at src/i18n/request.ts and adds the message catalogues to the build graph.
// So a locale added there is compiled in without a second registration, per ADR-0400.
const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const edgeOrigin = process.env.EDGE_PUBLIC_ORIGIN;
const allowedOrigins = edgeOrigin ? [new URL(edgeOrigin).host] : [];

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  // A workspace package of TypeScript source, not a built dependency.
  transpilePackages: ["@libs/id"],
  reactStrictMode: true,
  typedRoutes: true,
  // Emit browser source maps in the production build, per ADR-0503. Without them, a browser stack trace names minified chunks and offsets, and every fault shows as one unreadable frame.
  // They are BUILD artefacts, not served files. Collect them from the build and keep them per release. A public source map gives an attacker the unminified app.
  // `mise run frontend:sourcemaps` collects them.
  productionBrowserSourceMaps: true,
  // `cluster:full` serves the host-run `next dev` through the edge at dev.localtest.me:8443, which is a different origin from localhost.
  // Without this entry, Next blocks the cross-origin dev and HMR requests. Only the dev server reads it, and the prod build ignores it.
  allowedDevOrigins: ["dev.localtest.me"],
  experimental: {
    serverActions: {
      allowedOrigins,
    },
    // Enables `unauthorized()` and `forbidden()` from next/navigation and their file conventions, per ADR-0400. A denial reaches the user WITHOUT a redirect: the address bar still names the resource.
    // An error boundary has no status, misses a Server Action's return path, and shows every denial as a crash. src/app/forbidden.tsx decides the status on a streamed route.
    // The APIs are experimental and off by default. The app depends on one thrown error with `digest: "NEXT_HTTP_ERROR_FALLBACK;<status>"`, named only in src/lib/auth/denial.ts.
    authInterrupts: true,
    // `next/root-params` lets any server component read the `[locale]` root segment without props. i18n/request.ts needs it: the four no-props shells render before any page.
    // Those shells are loading, not-found, forbidden, and unauthorized. next-intl caches the config on its FIRST call per request.
    // Without this, the shell that renders first pins every later message to the default locale.
    rootParams: true,
  },
  env: {
    NEXT_PUBLIC_SERVICE_VERSION: process.env.SERVICE_VERSION ?? "dev",
    NEXT_PUBLIC_DEPLOY_ENV: process.env.DEPLOY_ENV ?? "dev",
  },
  // Set the shipped build's identity on every response, per ADR-0103. So response headers and devtools show whether prod updated.
  // A stale browser bundle shows when this value differs from the backend's X-App-Version.
  headers() {
    return Promise.resolve([
      {
        source: "/:path*",
        headers: [{ key: "X-App-Version", value: process.env.SERVICE_VERSION ?? "dev" }],
      },
    ]);
  },
};

export default withNextIntl(nextConfig);
