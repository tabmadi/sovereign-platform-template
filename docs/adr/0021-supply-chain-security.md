# ADR-0021: Supply-Chain Security

- **Status:** Accepted
- **Date:** 2026-07-06
- **Deciders:** Platform team
- **Related:** [ADR-0002](0002-monorepo.md), [ADR-0003](0003-cluster-topology.md), [ADR-0004](0004-gitops.md)

## Context

The platform runs first-party images built in CI plus third-party charts and images. `security-baseline.md`
deferred supply-chain controls per-instance; that leaves the provenance of what actually runs unverified.
At the target scale the controls must be CI-defaulted and enforced at admission, not manual audits.

## Decision drivers

1. **What runs is provably what we built** — signed, from our pipeline.
2. **Keyless over key management** — a small team should not run a signing-key HSM.
3. **Enforced at admission**, not just produced at build — an unsigned image must not schedule.
4. **In-tree with GitOps** ([ADR-0004](0004-gitops.md)); admission policy is files in the repo.

## Decision

- **Image signing: cosign keyless (OIDC).** CI signs every first-party image with cosign using the
  workflow's OIDC identity (Fulcio/Rekor), so there is no long-lived signing key to hold or rotate.
- **SBOM as an attestation.** CI generates an SBOM with syft (SPDX) and attaches it as a cosign
  attestation, so the bill of materials travels with the image.
- **Provenance attestation.** CI emits SLSA build provenance (what source, what builder) as an
  attestation.
- **Admission enforcement: Kyverno.** A cluster policy verifies the cosign signature and required
  attestations on first-party images and requires digest-pinned references (no floating tags,
  reinforcing [ADR-0002](0002-monorepo.md)). Unsigned or tag-floating images are rejected at admission.
- **Third-party images** are pinned by digest and allow-listed; verifying upstream signatures where the
  publisher provides them is preferred, tolerated as pinned-digest where they do not.
- **Scope:** signing/SBOM/provenance are build-time in CI; Kyverno is the runtime gate. Vulnerability
  *scanning* (e.g. Trivy in CI) is complementary and tracked in `security-baseline.md`.

## Consequences

### Positive

- The cluster runs only images it can prove came from our pipeline; the digest-pin rule closes tag drift.
- Keyless signing removes key custody from a small team.
- SBOM + provenance make incident response and CVE triage a lookup, not an archaeology dig.

### Negative / Risks

- Kyverno is a new platform component (admission controller) — Core-tier operational surface. Accepted;
  it is the enforcement point that makes the rest non-optional.
- Keyless signing depends on the CI OIDC provider and a transparency log; an outage there blocks signing,
  not running. Mitigated by signing only on release, not on every reconcile.

### Follow-ups

- cosign sign + SBOM (syft) + SLSA provenance steps in the image CI workflow.
- `infra/helm/platform/kyverno/` with the verify-signature + require-digest policies.
- Third-party image allow-list and digest pins.

## Rules

- Every first-party image is cosign-signed keyless (OIDC) in CI and carries an SBOM and provenance
  attestation. `(CI: image-workflow)`
- Kyverno rejects at admission any image lacking a valid signature or referenced by a floating tag; all
  images are digest-pinned ([ADR-0002](0002-monorepo.md)). `(CI: lint-floating-tags; enforced: Kyverno)`
- Third-party images are pinned by digest and allow-listed; upstream signatures are verified where
  published. `(review-only)`
