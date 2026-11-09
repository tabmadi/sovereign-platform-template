// The in-process API double for unit and component tests, per ADR-0400. E2e and visual tests never import it, per ADR-0601.
import type { paths as CatalogPaths } from "@sdks/catalog";
import type { components, paths as OrdersPaths } from "@sdks/orders";
import { HttpResponse, http } from "msw";
import { setupServer } from "msw/node";

export const server = setupServer();

export type Problem = components["schemas"]["Problem"];

type Method = "get" | "post" | "put" | "patch" | "delete";

type Success<Operation> = Operation extends {
  responses: { 200: { content: { "application/json": infer Body } } };
}
  ? Body
  : Operation extends { responses: { 201: { content: { "application/json": infer Body } } } }
    ? Body
    : Operation extends { responses: { 202: { content: { "application/json": infer Body } } } }
      ? Body
      : never;

// The browser seam calls every service under `/api`, so `/orders/{id}` becomes `*/api/orders/:id`.
function pattern(path: string): string {
  return `*/api${path.replaceAll(/\{(\w+)\}/g, ":$1")}`;
}

// Handlers typed by the generated SDK of one service, per ADR-0303. A path or a body that the spec does not have fails tsc.
function typed<Paths>() {
  return {
    ok<Path extends keyof Paths & string, M extends Method & keyof Paths[Path]>(
      method: M,
      path: Path,
      body: Success<Paths[Path][M]>,
      status = 200,
    ) {
      return http[method](pattern(path), () => HttpResponse.json(body as object, { status }));
    },
    problem<Path extends keyof Paths & string>(method: Method, path: Path, problem: Problem) {
      return http[method](pattern(path), () =>
        HttpResponse.json(problem, {
          status: problem.status,
          headers: { "Content-Type": "application/problem+json" },
        }),
      );
    },
  };
}

export const catalogApi = typed<CatalogPaths>();
export const ordersApi = typed<OrdersPaths>();
