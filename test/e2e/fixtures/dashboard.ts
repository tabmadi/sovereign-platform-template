// Shared staged helpers for the gated ops dashboards, per ADR-0306.
import { type APIRequestContext, expect, request } from "@playwright/test";
import { OPERATOR_STATE, USER_STATE, opsURL } from "./env";

// Under suite load, the local resolver can answer a *.ops lookup with a transient EAI_AGAIN. These tests do not look for that signal. A real 401, 403, or 200 returns at once.
async function statusFor(
  tool: string,
  storageState?: string,
): Promise<{ status: number; location: string }> {
  const ctx: APIRequestContext = await request.newContext({
    ignoreHTTPSErrors: true,
    storageState,
  });
  try {
    let lastErr: unknown;
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        const res = await ctx.get(`${opsURL(tool)}/`, {
          maxRedirects: 0,
          headers: { accept: "*/*" },
        });
        return { status: res.status(), location: res.headers().location ?? "" };
      } catch (err) {
        // Retry only transient name-resolution or connection errors, never a real HTTP response.
        // get() resolves for any status, so a response never throws.
        if (!/EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ECONNRESET/.test(String(err))) {
          throw err;
        }
        lastErr = err;
        await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
      }
    }
    throw lastErr;
  } finally {
    await ctx.dispose();
  }
}

export async function expectUnauthenticatedDenied(tool: string): Promise<void> {
  expect([401, 302, 303]).toContain((await statusFor(tool)).status);
}

export async function expectAal1Forbidden(tool: string): Promise<void> {
  expect([403, 302, 303]).toContain((await statusFor(tool, USER_STATE)).status);
}

// A 200 is the tool answering. A redirect from the tool to its own origin is also the tool answering.
// A check on the status alone calls that a failure, after it proved that the grant works.
// It cannot be a denial: Oathkeeper's html branch redirects to a different origin.
export async function expectOperatorAllowed(tool: string): Promise<void> {
  const { status, location } = await statusFor(tool, OPERATOR_STATE);
  if (status === 200) {
    return;
  }
  // Resolve against the tool's origin. A tool's own redirect is usually path-only, such as `/login`, and the edge's redirect is absolute and elsewhere.
  const target = location ? new URL(location, `${opsURL(tool)}/`).href : "";
  expect(
    [301, 302, 303, 307, 308].includes(status) && target.startsWith(`${opsURL(tool)}/`),
    `operator was not passed through to ${tool}: ${status} → ${target || "no location"}`,
  ).toBe(true);
}
