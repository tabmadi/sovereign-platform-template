// Next.js config of the admin console, per ADR-0401. The image runs the standalone server on Node.js, like the frontend.

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  reactStrictMode: true,
  // The repository keeps one AGENTS.md at its root, so `next dev` must not write its own.
  agentRules: false,
  // The console has its own ops origin, per ADR-0306. Server Actions then pass the check of Origin against Host.
  experimental: { serverActions: { allowedOrigins: [] } },
  poweredByHeader: false,
};

export default nextConfig;
