// Cross-service mutation polling, per ADR-0302 and ADR-0400: a service that starts a workflow answers 202 with a handle.
export type WorkflowHandle = {
  id: string;
  run_id: string;
  // Temporal run status at enqueue time. It is always `running` for a new handle.
  status: "running" | "completed" | "failed" | "cancelled";
  // GET to fetch the terminal status and result. Only a handle that carries the result inline omits it.
  result_url?: string;
};

import { raiseForAuthDenial } from "@/lib/auth/denial";

// The terminal-state shape of the resources that a workflow settles, orders and charges: a domain status string. `pending` and `running` are not terminal.
export type TerminalResource = { status: string };

const TERMINAL = new Set(["confirmed", "completed", "failed", "cancelled", "settled", "refunded"]);

type PollOpts = {
  intervalMs?: number;
  timeoutMs?: number;
  // How long a 403 on the polled resource means that the grant has not arrived yet, and not a denial. See the note in the loop below.
  forbiddenGraceMs?: number;
  signal?: AbortSignal;
};

// Resolves on the first terminal status, success or failure: a failed charge is a completed poll, not an error.
export async function pollWorkflow<T extends TerminalResource>(
  handle: WorkflowHandle,
  { intervalMs = 1000, timeoutMs = 60_000, forbiddenGraceMs = 10_000, signal }: PollOpts = {},
): Promise<T> {
  if (!handle.result_url) {
    throw new Error("workflow handle has no result_url to poll");
  }
  const deadline = Date.now() + timeoutMs;
  const graceEnds = Date.now() + forbiddenGraceMs;
  // biome-ignore lint/suspicious/noUnnecessaryConditions: poll loop exits via return/throw below
  while (true) {
    if (signal?.aborted) {
      throw new Error("aborted");
    }
    // biome-ignore lint/performance/noAwaitInLoops: workflow polling is intentionally sequential
    const res = await fetch(handle.result_url, { cache: "no-store", signal });
    // A denial ends this poll. Otherwise every non-ok status means not settled yet, and an expired session waits until the timeout.
    // One exception: the workflow's first leg writes the resource and the tuples that say who can read it, per ADR-0304.
    // So a 403 inside the grace period is a checkout that is about to succeed. A 401 never waits.
    if (res.status !== 403 || Date.now() > graceEnds) {
      raiseForAuthDenial(res.status);
    }
    if (res.ok) {
      const body = (await res.json()) as T;
      if (TERMINAL.has(body.status)) {
        return body;
      }
    }
    if (Date.now() > deadline) {
      throw new Error("workflow poll timed out before reaching a terminal status");
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}
