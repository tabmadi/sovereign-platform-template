// Shared response assertions for k6 scenarios, per ADR-0601.
//
// A k6 `check` records a pass or fail rate. Unlike a test assertion, it does NOT fail the run on its own, and this is deliberate:
// under load, some failures are the finding, not an error. A threshold in the scenario's options fails a run,
// and every helper below feeds the `checks` rate that those thresholds use.
import { check } from "k6";

// expectStatus asserts the response code and that a body came back. The body check catches a local failure:
// Traefik answers with an empty 200 because an upstream went away during the run.
export function expectStatus(res, want, name) {
  return check(res, {
    [`${name}: status ${want}`]: (r) => r.status === want,
    [`${name}: body present`]: (r) => r.body !== null && r.body.length > 0,
  });
}

// expectJSON asserts a JSON body and passes the parsed value to a predicate. Parsing is guarded:
// an RFC 7807 problem document from libs/go/apierr and an HTML error page from the edge are both unexpected JSON,
// and a bare JSON.parse would stop the VU's iteration and record no check.
export function expectJSON(res, name, predicate) {
  let parsed = null;
  try {
    parsed = res.json();
  } catch {
    parsed = null;
  }
  const ok = check(res, {
    [`${name}: parses as JSON`]: () => parsed !== null,
    [`${name}: shape valid`]: () => parsed !== null && predicate(parsed),
  });
  return { ok, body: parsed };
}
