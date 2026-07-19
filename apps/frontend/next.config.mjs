// Next.js config (ADR-0014). Standalone output is required for the Bun-only
// Dockerfile. All first-party code lives inside the app, so no transpilePackages.

// Server Actions CSRF allowlist (ADR-0009, ADR-0014). Next checks the request
// Origin against this list; pair it with the edge Origin check and SameSite=Lax
// session cookie. Set APP_ORIGIN per env (e.g. dev.example.com).
const appOrigin = process.env.APP_ORIGIN;
const allowedOrigins = appOrigin ? [appOrigin] : [];

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  reactStrictMode: true,
  typedRoutes: true,
  // `cluster:full` serves the host-run `next dev` through the edge at
  // dev.localtest.me:8443 — a different origin than localhost — so allow it,
  // otherwise Next blocks the cross-origin dev/HMR requests. Dev-server-only;
  // the prod build ignores it.
  allowedDevOrigins: ["dev.localtest.me"],
  experimental: {
    serverActions: {
      allowedOrigins,
    },
  },
  env: {
    NEXT_PUBLIC_SERVICE_VERSION: process.env.SERVICE_VERSION ?? "dev",
    NEXT_PUBLIC_DEPLOY_ENV: process.env.DEPLOY_ENV ?? "dev",
  },
  // Stamp the shipped build's identity on every response (ADR-0013), so "did prod
  // actually update?" is answerable from response headers / devtools, and a stale
  // browser bundle is caught by comparing this against the backend's X-App-Version.
  headers() {
    return Promise.resolve([
      {
        source: "/:path*",
        headers: [{ key: "X-App-Version", value: process.env.SERVICE_VERSION ?? "dev" }],
      },
    ]);
  },
};

export default nextConfig;
