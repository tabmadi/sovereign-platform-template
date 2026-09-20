// Liveness/readiness endpoint for the in-cluster frontend (ADR-0500, ADR-0205).
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" });
}
