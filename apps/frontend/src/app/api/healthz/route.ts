// Liveness and readiness endpoint for the in-cluster frontend, per ADR-0500 and ADR-0205.
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" });
}
