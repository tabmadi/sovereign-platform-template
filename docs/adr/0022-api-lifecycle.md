# ADR-0022: API Lifecycle & Versioning

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0008](0008-api-contracts.md), [ADR-0009](0009-api-gateway.md), [ADR-0013](0013-release-and-versioning.md), [ADR-0014](0014-frontend.md), [ADR-0017](0017-url-and-domain-structure.md)

## Context

[ADR-0008](0008-api-contracts.md) pins the API contract (OpenAPI 3.1) and breaking-change *detection*, and
[ADR-0013](0013-release-and-versioning.md) pins release tagging. Neither says how a live API evolves: how a
consumer that cannot upgrade in lockstep is carried across a breaking change.

The deciding fact is **who consumes the API**. Today there is exactly one consumer: the Next.js frontend
([ADR-0014](0014-frontend.md)), which **ships in the same commit and deploys in the same release** as the
services it calls. A breaking API change and its caller change land in one PR and go out together; the old
shape never has to exist after the deploy. There is nothing to be backwards-compatible *with*.

A separate, versioned public API is a flag away ([ADR-0009](0009-api-gateway.md)) — but until an external
consumer that we *cannot force to upgrade* exists, keeping two API shapes alive at once is machinery paid for
a problem we do not have. The trap this ADR exists to prevent is building that machinery prematurely (a small
team cannot afford to operate two live majors), and the opposite trap of having no written plan when the first
external consumer finally appears.

## Decision drivers

1. **Match the consumer reality.** A single co-shipped consumer needs no online version; an uncontrolled
   external consumer needs one. The default must be the first, with the second a documented, deferred upgrade.
2. **Breaking vs non-breaking stays mechanical**, tied to the contract diff already in CI
   ([ADR-0008](0008-api-contracts.md)) — but in the default world it is a *review signal*, not a version gate.
3. **Small-team affordability.** The default operates zero extra moving parts: no version header, no support
   window, no transformation layer.
4. **A known upgrade path.** When an external consumer arrives, the versioning scheme is already chosen and
   written, so nobody re-invents it under pressure.

## Decision

### Default: one live version, and it *is* the production release

The template default is **single-live-version**. The API is **unversioned in practice**: there is no version
in the path, no version header, and no support window. The live API is whatever the current production release
([ADR-0013](0013-release-and-versioning.md)) serves.

- **A breaking change is a normal PR.** Because the only consumer is the co-shipped frontend
  ([ADR-0014](0014-frontend.md)), a breaking API change updates the caller in the same commit; they deploy
  together. The previous shape is not kept alive.
- **The contract diff is a review signal, not a gate.** `oasdiff` ([ADR-0008](0008-api-contracts.md)) still
  runs and still labels a change breaking — so a break is always *intentional and visible in review*, never
  accidental — but a breaking change does **not** require a version bump or a second live surface.
- **No `Deprecation`/`Sunset` machinery, no transformation layer, no N-1.** These belong to the deferred
  public-API path below and are not built for the default.

This is the industry-standard choice for a single, co-shipped consumer (the "evolve the API, don't fork it"
position). Versioning schemes exist to protect consumers you cannot force to upgrade; with one consumer that
ships in-tree, that cost buys nothing.

### Deferred upgrade: date-based versioning for external consumers (flagged)

When a project exposes the API to consumers it **cannot deploy in lockstep** — third parties, partners, or
even a first-party mobile app on its own release cadence — it turns on online versioning at that point. This is
the same "flag away" model as Hydra for public auth ([ADR-0009](0009-api-gateway.md)): the design is decided
here so it is not improvised later, but **nothing is built or operated until the flag is on**.

When flipped, the scheme is:

- **Date-based version in a request header** (`Api-Version: 2026-07-01`), not in the path. This keeps the flat
  resource URL ([ADR-0017](0017-url-and-domain-structure.md)) stable across versions and matches the dominant
  convention for continuously-evolving REST APIs (Stripe, GitHub, Azure). A version date is drawn from the same
  calendar as the release ([ADR-0013](0013-release-and-versioning.md)): it is *the subsequence of release dates
  on which the public contract changed in a consumer-visible way*, so every API version traces back to a real
  release, and most releases mint no new API version.
- **A missing header resolves to the latest version**, and the resolved date is echoed in the response;
  external clients are advised to pin explicitly. (This question does not arise in the default world — there is
  no header.)
- **Support window: N-1.** At most two versions are live at once; the previous is served through a documented
  sunset window, then removed. A deprecated version returns `Deprecation` (RFC 9745) + `Sunset` (RFC 8594) +
  `Link` to migration notes.
- **Backwards compatibility by transformation, bounded to N-1.** Handlers only ever produce the latest shape; a
  thin response-compatibility layer transforms it back to the one previous version (the Stripe model, but
  bounded to a single prior shape by N-1 — not an open-ended replay engine).

### Why date-based, not SemVer-major-in-path (recorded for when the flag flips)

- A path major (`/api/v2/...`) fights the flat, topology-hidden resource URL this platform adopted
  ([ADR-0017](0017-url-and-domain-structure.md)); a header carries the version without forking the URL.
- SemVer's value is the *breaking signal* to an independent pinner. On the public API that signal is delivered
  by the pin-and-sunset discipline (an unpinned client is never silently upgraded across a break), so a bare
  date suffices and keeps one calendar across release and contract ([ADR-0013](0013-release-and-versioning.md)).
- Even the path-major shops (Google AIP) expose only the major — never minor/patch — and serve both majors from
  one backend; date-header versioning is the same idea with a finer, calendar-aligned label.

## Consequences

### Positive

- The default operates like the team already works: cut a release, it replaces the last one, done. Zero
  version machinery to run.
- A breaking change is honest and reviewable (oasdiff labels it) without forcing a second live surface.
- The public-API path is fully designed and written, so flipping the flag is a planned upgrade, not a scramble.
- One calendar spans release and (eventual) API version — no second versioning vocabulary.

### Negative / Risks

- The default cannot serve an out-of-lockstep consumer at all: the first mobile app or partner integration is
  the trigger to flip the flag, and until it is flipped such a consumer is unsupported. Accepted — that trigger
  is explicit here.
- Turning on the flag introduces the transformation layer and a support window (real cost). Bounded by N-1 and
  deferred until a paying reason exists.

### Follow-ups

- oasdiff wired as a **labelling/review** step in CI ([ADR-0008](0008-api-contracts.md)), not a version gate.
- When the flag is added: `Api-Version` header negotiation at the edge/service, the N-1 response-compat layer,
  the `Deprecation`/`Sunset`/`Link` emission, and a small `docs/api-versions.md` registry recording which
  release dates are contract boundaries and their sunset dates.

## Rules

- The template default is **single-live-version**: the live API is the current production release
  ([ADR-0013](0013-release-and-versioning.md)); there is no version in the path or a header, and no support
  window. `(review-only)`
- A breaking contract change is allowed and ships in one PR with its co-shipped caller
  ([ADR-0014](0014-frontend.md)); the previous shape is not kept alive. `(review-only)`
- `oasdiff` ([ADR-0008](0008-api-contracts.md)) labels breaking changes for review so a break is intentional; in
  the default it is **not** a version gate and does **not** require a bump. `(CI: ci-contract)`
- Online versioning (date-based `Api-Version` header, N-1 support window, `Deprecation`/`Sunset`/`Link`, and an
  N-1-bounded response-transformation layer) is a **deferred, flagged** upgrade, turned on only when a consumer
  that cannot deploy in lockstep exists. It is not built or operated in the default. `(review-only)`
- When online versioning is on: a missing `Api-Version` resolves to the latest and the resolved date is echoed;
  at most two versions are live (N-1); each API version date traces to a real release
  ([ADR-0013](0013-release-and-versioning.md)). `(review-only)`
