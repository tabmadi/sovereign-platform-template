// The calls from the console server to the service APIs, east-west on each server port, per ADR-0401.
// They never pass the `/api` edge. The browser never calls a service.
import "server-only";

// The services trust this fixed subject for writes. The OpenFGA seed grants it group:operator, per ADR-0305.
const CONSOLE_SUBJECT = "admin-console";

/** The base URL of one service. ADMIN_SERVICE_URL names `{service}` once, and the default is the in-cluster address. */
export function serviceURL(service: string): string {
  const template =
    process.env.ADMIN_SERVICE_URL ?? "http://{service}-server.platform.svc.cluster.local";
  return template.replace("{service}", service);
}

export type Result = { ok: true; data: unknown } | { ok: false; error: string };

export async function call(
  service: string,
  method: string,
  path: string,
  body?: unknown,
): Promise<Result> {
  const headers: Record<string, string> = {
    "X-User-Id": CONSOLE_SUBJECT,
    Accept: "application/json",
  };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }
  let res: Response;
  try {
    res = await fetch(`${serviceURL(service)}${path}`, {
      method: method.toUpperCase(),
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
    });
  } catch (err) {
    return { ok: false, error: `${service} is not reachable: ${(err as Error).message}` };
  }
  const text = await res.text();
  let data: unknown = text;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    // A body that is not JSON stays text.
  }
  if (!res.ok) {
    // A problem+json body names the reason in `detail` or `title`, per ADR-0303.
    const detail =
      typeof data === "object" && data !== null ? (data as Record<string, unknown>) : {};
    const reason = String(detail.detail ?? detail.title ?? text ?? "").trim();
    return {
      ok: false,
      error: `${method.toUpperCase()} ${path} returned ${res.status}${reason ? `: ${reason}` : ""}`,
    };
  }
  return { ok: true, data };
}
