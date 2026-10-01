// Kratos session gate and a CSP nonce for each request, per ADR-0304, ADR-0400, and ADR-0305.
import { match as matchLocale } from "@formatjs/intl-localematcher";
import { type NextRequest, NextResponse } from "next/server";
import { isLocale, LOCALE_COOKIE, type Locale, routing } from "@/i18n/routing";

const SESSION_COOKIE = "ory_kratos_session";

// `/analytics` is here only for the session part. The route group does the authoritative check itself, per ADR-0700, and a redirect is a better first experience than a 403.
const PROTECTED = ["/panel", "/devportal", "/analytics"];

// A Kratos browser flow cannot start on our side: Kratos sets its CSRF cookie and returns a flow id.
// The redirect is issued here and not from the page, because this measurably improves LCP, per ADR-0400.
// The path segment is not always the flow name: /auth/register starts `registration`.
const AUTH_FLOWS: Record<string, string> = {
  login: "login",
  register: "registration",
  recovery: "recovery",
  verification: "verification",
  settings: "settings",
};

// Kratos refuses these with `session_already_available` and sends the browser to the return URL.
// Without this, the back button after sign-in moves the user to the landing page. `settings` and `verification` are absent: both are useful while signed in.
const SIGNED_IN_HAS_NO_FLOW = new Set(["login", "register", "recovery"]);

// Telemetry ingest origin for connect-src. By default it is same-origin, /api/rum through Traefik. Override it when RUM goes to a different host.
const INGEST_ORIGIN = process.env.NEXT_PUBLIC_OTEL_INGEST_ORIGIN ?? "";

// next-intl's middleware does the rewrite, and so does this file. Two cannot both rewrite, and the CSP nonce must be on the rewritten request's headers.
// A second middleware's response drops those headers. The matching uses RFC 4647 lookup, from the same library that next-intl uses.

/** Split a pathname into its locale prefix, if there is one, and the rest. */
function splitLocale(pathname: string): { prefix: Locale | null; rest: string } {
  const [, first = "", ...others] = pathname.split("/");
  if (isLocale(first)) {
    return { prefix: first, rest: `/${others.join("/")}` };
  }
  return { prefix: null, rest: pathname };
}

/**
 * The locale for a request with no prefix: the cookie from an earlier visit, then the browser's preference, then the default.
 * A cookie wins over `Accept-Language`: an explicit choice ranks above a header that the reader never set.
 */
function negotiateLocale(req: NextRequest): Locale {
  const fromCookie = req.cookies.get(LOCALE_COOKIE)?.value;
  if (fromCookie && isLocale(fromCookie)) {
    return fromCookie;
  }
  const header = req.headers.get("accept-language");
  if (!header) {
    return routing.defaultLocale;
  }
  const requested = header
    .split(",")
    .map((part) => part.split(";")[0]?.trim())
    .filter((tag): tag is string => Boolean(tag));
  try {
    return matchLocale(requested, routing.locales, routing.defaultLocale) as Locale;
  } catch {
    // A tag that does not parse is a bad header, not an outage.
    return routing.defaultLocale;
  }
}

/** Prefix a path for a locale. The default locale has no prefix, per the as-needed mode. */
function localised(path: string, locale: Locale): string {
  return locale === routing.defaultLocale ? path : `/${locale}${path}`;
}

function makeNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

function contentSecurityPolicy(nonce: string): string {
  const connectSrc = ["'self'", INGEST_ORIGIN].filter(Boolean).join(" ");
  // `next dev` injects inline HMR scripts with no nonce and needs eval. strict-dynamic makes the browser ignore 'unsafe-inline', so the dev server gets a policy that allows inline code.
  const scriptSrc =
    process.env.NODE_ENV === "production"
      ? ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'"]
      : ["'self'", "'unsafe-inline'", "'unsafe-eval'"];
  return [
    "default-src 'self'",
    `script-src ${scriptSrc.join(" ")}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    `connect-src ${connectSrc}`,
    "font-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join("; ");
}

// An attacker can control a `return_to`, so only a same-site absolute path is followed. Kratos checks it on the flow side, and this function also reads it from a URL that Kratos never saw.
function safeReturnTo(raw: string | null): string | null {
  if (!raw?.startsWith("/") || raw.startsWith("//")) {
    return null;
  }
  return raw;
}

function isProtected(path: string): boolean {
  return PROTECTED.some((p) => path === p || path.startsWith(`${p}/`));
}

function authFlowFor(path: string): { segment: string; kind: string | undefined } {
  const segment = path.startsWith("/auth/") ? path.slice("/auth/".length) : "";
  return { segment, kind: AUTH_FLOWS[segment] };
}

/**
 * A flow id means that Kratos asked for this flow, and that wins over the shortcut. An operator who steps up to aal2 has both a session and a flow.
 * Sending them home means that the second factor never shows.
 */
function signedInHasNoFlowToStart(segment: string, hasSession: boolean, hasFlow: boolean): boolean {
  return hasSession && !hasFlow && SIGNED_IN_HAS_NO_FLOW.has(segment);
}

/** An answer here keeps the reader inside the app, and keeps any `return_to` in the URL. */
function redirectHome(req: NextRequest, locale: Locale): NextResponse {
  const back = safeReturnTo(req.nextUrl.searchParams.get("return_to")) ?? localised("/", locale);
  return NextResponse.redirect(new URL(back, req.url));
}

/** `/auth/self-service/*` is the Kratos URL space behind Traefik, so it is never localised, per ADR-0306. */
function startKratosFlow(req: NextRequest, flowKind: string): NextResponse {
  const start = new URL(`/auth/self-service/${flowKind}/browser`, req.url);
  const returnTo = safeReturnTo(req.nextUrl.searchParams.get("return_to"));
  if (returnTo) {
    start.searchParams.set("return_to", returnTo);
  }
  return NextResponse.redirect(start);
}

/** The panel keeps filters, pagination, and tab selection in the URL through nuqs, so the query is part of where the reader was. */
function pathWithQuery(req: NextRequest): string {
  return `${req.nextUrl.pathname}${req.nextUrl.search}`;
}

function redirectToLogin(req: NextRequest, locale: Locale): NextResponse {
  const login = new URL(localised("/auth/login", locale), req.url);
  login.searchParams.set("return_to", pathWithQuery(req));
  return NextResponse.redirect(login);
}

/** The root layout sets this nonce on its own `<script>` tags, so the nonce goes on the request. */
function requestHeadersWithNonce(req: NextRequest, nonce: string, csp: string): Headers {
  const headers = new Headers(req.headers);
  headers.set("x-nonce", nonce);
  headers.set("content-security-policy", csp);
  return headers;
}

/**
 * The `[locale]` segment is always present internally. So an unprefixed request is rewritten to the negotiated locale, and the address bar keeps the clean URL.
 * A prefixed request already matches and needs no rewrite.
 */
function localeRewriteTarget(
  req: NextRequest,
  prefix: Locale | null,
  locale: Locale,
  path: string,
): URL | null {
  if (prefix !== null) {
    return null;
  }
  const rewritten = req.nextUrl.clone();
  rewritten.pathname = `/${locale}${path === "/" ? "" : path}`;
  return rewritten;
}

/** `lax`, because a locale is a preference and not a credential, and it must survive a cross-site navigation back. */
function rememberLocale(req: NextRequest, res: NextResponse, locale: Locale): void {
  if (req.cookies.get(LOCALE_COOKIE)?.value === locale) {
    return;
  }
  res.cookies.set(LOCALE_COOKIE, locale, {
    path: "/",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
  });
}

export function proxy(req: NextRequest) {
  // Locale first: every decision below uses the path without its prefix. In the other order, `/de/panel` would be unprotected.
  const { prefix, rest } = splitLocale(req.nextUrl.pathname);
  const locale = prefix ?? negotiateLocale(req);
  const path = rest === "" ? "/" : rest;

  const hasSession = req.cookies.get(SESSION_COOKIE) !== undefined;
  const hasFlow = req.nextUrl.searchParams.get("flow") !== null;
  const { segment, kind: flowKind } = authFlowFor(path);

  if (flowKind && signedInHasNoFlowToStart(segment, hasSession, hasFlow)) {
    return redirectHome(req, locale);
  }
  if (flowKind && !hasFlow) {
    return startKratosFlow(req, flowKind);
  }

  let session: string | undefined;
  if (isProtected(path)) {
    session = req.cookies.get(SESSION_COOKIE)?.value;
    if (!session) {
      return redirectToLogin(req, locale);
    }
  }

  const nonce = makeNonce();
  const csp = contentSecurityPolicy(nonce);
  const headers = requestHeadersWithNonce(req, nonce, csp);
  const rewriteTo = localeRewriteTarget(req, prefix, locale, path);
  const res = rewriteTo
    ? NextResponse.rewrite(rewriteTo, { request: { headers } })
    : NextResponse.next({ request: { headers } });

  res.headers.set("content-security-policy", csp);
  if (session) {
    res.headers.set("x-kratos-session", session);
  }
  rememberLocale(req, res, locale);
  return res;
}

export const config = {
  // Apply CSP to every document and route except static assets.
  matcher: [
    {
      source: "/((?!_next/static|_next/image|favicon.ico).*)",
    },
  ],
};
