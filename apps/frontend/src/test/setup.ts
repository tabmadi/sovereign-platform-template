// The Vitest setup file of apps/frontend/vitest.config.ts: a happy-dom window and the MSW server around every test, per ADR-0400.
import { GlobalRegistrator } from "@happy-dom/global-registrator";

// happy-dom's fetch opens its own sockets, which MSW does not see. So the tests keep the fetch of Node.js and its classes.
// The fetch of Node.js pipes bodies through the stream classes of Node.js, so the tests keep those too.
const {
  fetch,
  Request,
  Response,
  Headers,
  FormData,
  Blob,
  ReadableStream,
  WritableStream,
  TransformStream,
  AbortController,
  AbortSignal,
} = globalThis;
GlobalRegistrator.register({ url: "http://localhost/" });

// A browser resolves a relative URL such as `/api/orders` against the page. The Request of Node.js has no page, and openapi-fetch builds one.
class PageRequest extends Request {
  constructor(input: RequestInfo | URL, init?: RequestInit) {
    const relative = typeof input === "string" && !URL.canParse(input);
    super(relative ? new URL(input, location.href) : input, init);
  }
}

Object.assign(globalThis, {
  fetch,
  Request: PageRequest,
  Response,
  Headers,
  FormData,
  Blob,
  ReadableStream,
  WritableStream,
  TransformStream,
  AbortController,
  AbortSignal,
});

const { afterAll, afterEach, beforeAll } = await import("vitest");
const { cleanup } = await import("@testing-library/react");
const { server } = await import("./msw");

// A request with no handler fails the test, so no test reaches a real network.
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
  server.events.removeAllListeners();
});
afterAll(() => server.close());
