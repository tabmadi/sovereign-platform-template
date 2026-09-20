// Kratos session gate + per-request CSP nonce (ADR-0304, ADR-0400, ADR-0305).
import { match as matchLocale } from "@formatjs/intl-localematcher";
import { type NextRequest, NextResponse } from "next/server";
import { isLocale, LOCALE_COOKIE, type Locale, routing } from "@/i18n/routing";

const SESSION_COOKIE = "ory_kratos_session";

// `/analytics` is here for the session half only: the route group performs the authoritative check itself (ADR-0700), and a redirect beats a 403 as a first experience.
const PROTECTED = ["/panel", "/devportal", "/analytics"];

// A Kratos browser flow cannot begin on our side: Kratos sets its CSRF cookie and hands back a flow id.
// Issuing the redirect here rather than from the page is a measured LCP fix (ADR-0400).
// The path segment is not always the flow name: /auth/register starts `registration`.
const AUTH_FLOWS: Record<string, string> = {
  login: "login",
  register: "registration",
  recovery: "recovery",
  verification: "verification",
  settings: "settings",
};

// Kratos refuses these with `session_already_available` and sends the browser to the return URL, so without this
// the back button after sign-in teleports the user to the landing page.
// `settings` and `verification` are absent: both are meaningful while signed in.
const SIGNED_IN_HAS_NO_FLOW = new Set(["login", "register", "recovery"]);

// Telemetry ingest origin for connect-src. Same-origin (/api/rum via Traefik)
// by default; override when RUM ships to a distinct host.
const INGEST_ORIGIN = process.env.NEXT_PUBLIC_OTEL_INGEST_ORIGIN ?? "";

// next-intl's middleware owns the rewrite, and so does this file; two cannot both rewrite, and the CSP nonce
// must travel on the rewritten request's headers, which a second middleware's response discards.
// The matching itself is not hand-rolled: RFC 4647 lookup, the same library next-intl uses.

/** Split a pathname into its locale prefix, if any, and the rest. */
function splitLocale(pathname: string): { prefix: Locale | null; rest: string } {
  const [, first = "", ...others] = pathname.split("/");
  if (isLocale(first)) {
    return { prefix: first, rest: `/${others.join("/")}` };
  }
  return { prefix: null, rest: pathname };
}

/**
 * The locale for a request with no prefix: the cookie a previous visit wrote, then the browser's preference,
 * then the default. A cookie beats `Accept-Language`: an explicit choice outranks a header the reader never set.
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
    // An unparseable tag is a header, not an outage.
    return routing.defaultLocale;
  }
}

/** Prefix a path for a locale, leaving the default locale unprefixed (as-needed). */
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
  // `next dev` injects un-nonced inline HMR scripts and needs eval, and strict-dynamic makes the browser ignore 'unsafe-inline', so the dev server gets an inline-permissive policy.
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

// A `return_to` is attacker-controllable, so only a same-site absolute path is followed. Kratos applies its own check on the flow side; this function also reads the parameter off a URL Kratos never saw.
function safeReturnTo(raw: string | null): string | null {
  if (!raw?.startsWith("/") || raw.startsWith("//")) {
    return null;
  }
  return raw;
}

export function proxy(req: NextRequest) {
  // Locale first: every decision below is made on the path without its prefix. The other way round is how `/de/panel` ends up unprotected.
  const { prefix, rest } = splitLocale(req.nextUrl.pathname);
  const locale = prefix ?? negotiateLocale(req);
  const path = rest === "" ? "/" : rest;

  const isProtected = PROTECTED.some((p) => path === p || path.startsWith(`${p}/`));
  const hasSession = req.cookies.get(SESSION_COOKIE) !== undefined;

  const authSegment = path.startsWith("/auth/") ? path.slice("/auth/".length) : "";
  const flowKind = AUTH_FLOWS[authSegment];

  // Answering here keeps the user inside the app and keeps whatever `return_to` the URL carries.
  // Unless the URL carries a flow id: an operator stepping up to aal2 arrives with a session and a flow, and bouncing it home means the second factor can never be presented.
  const hasFlow = req.nextUrl.searchParams.get("flow") !== null;
  if (flowKind && hasSession && !hasFlow && SIGNED_IN_HAS_NO_FLOW.has(authSegment)) {
    const back = safeReturnTo(req.nextUrl.searchParams.get("return_to")) ?? localised("/", locale);
    return NextResponse.redirect(new URL(back, req.url));
  }

  // An /auth/* page with no flow id: send the browser to Kratos to start one. The Kratos path is not localised — `/auth/self-service/*` is Kratos's URL space behind Traefik (ADR-0306).
  if (flowKind && !hasFlow) {
    const start = new URL(`/auth/self-service/${flowKind}/browser`, req.url);
    const returnTo = safeReturnTo(req.nextUrl.searchParams.get("return_to"));
    if (returnTo) {
      start.searchParams.set("return_to", returnTo);
    }
    return NextResponse.redirect(start);
  }

  let session: string | undefined;
  if (isProtected) {
    session = req.cookies.get(SESSION_COOKIE)?.value;
    if (!session) {
      const login = new URL(localised("/auth/login", locale), req.url);
      // Path AND query. The panel keeps filters, pagination and tab selection in
      // the URL through nuqs, so a `return_to` of the bare pathname hands the user
      // back a screen they did not leave — the session expired, not the view.
      login.searchParams.set("return_to", `${req.nextUrl.pathname}${req.nextUrl.search}`);
      return NextResponse.redirect(login);
    }
  }

  const nonce = makeNonce();
  const csp = contentSecurityPolicy(nonce);

  // Forward the nonce + CSP on the request so the root layout can stamp the
  // nonce onto its <script> tags.
  const requestHeaders = new Headers(req.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("content-security-policy", csp);

  // The `[locale]` segment must always be present internally, so an unprefixed
  // request is rewritten onto the negotiated locale while the address bar keeps the
  // clean URL. A prefixed request already matches and is passed through.
  const rewritten = req.nextUrl.clone();
  rewritten.pathname = `/${locale}${path === "/" ? "" : path}`;
  const res =
    prefix === null
      ? NextResponse.rewrite(rewritten, { request: { headers: requestHeaders } })
      : NextResponse.next({ request: { headers: requestHeaders } });

  res.headers.set("content-security-policy", csp);
  if (session) {
    res.headers.set("x-kratos-session", session);
  }
  // Remember a negotiated or chosen locale, so the second visit does not re-derive
  // it from a header the reader never set. `lax` because this is a preference, not a
  // credential, and it must survive a cross-site navigation back into the app.
  if (req.cookies.get(LOCALE_COOKIE)?.value !== locale) {
    res.cookies.set(LOCALE_COOKIE, locale, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 365,
    });
  }
  return res;
}

export const config = {
  // Apply CSP to every document/route except static assets.
  matcher: [
    {
      source: "/((?!_next/static|_next/image|favicon.ico).*)",
    },
  ],
};
