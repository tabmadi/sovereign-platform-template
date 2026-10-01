# ADR-0104: Supply-Chain Security

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0102](0102-source-control-and-ci.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0105](0105-image-registry.md), [ADR-0201](0201-gitops.md), [ADR-0203](0203-policy-enforcement.md)
- **Decides:** Images are signed by a cosign key pair held in SOPS, carry syft SBOM and SLSA provenance attestations, and are verified at admission.

## Context

The platform runs first-party images built in CI, plus third-party charts and images. With no control, the provenance of a running image is inferred from the registry it came from. A registry records where a thing was found, not who made it.

The platform team is small compared with the whole fleet, per [ADR-0000](0000-platform-foundations.md). It also grows much more slowly than the fleet. So CI must apply the controls by default, and admission must enforce them. A manual audit does not scale and does not block.

## Decision drivers

1. **The origin of a running image is verifiable.** It is not inferred from where the image was found.
2. **No hardware custody and no credential held by a human.** A team this size cannot operate an HSM. A key that a person can copy is not a signing identity. The key must sit in machinery that the platform already runs.
3. **A control that the constrained party can bypass is not a control.** The gate for an image must sit where the deploying party cannot route around it.
4. **In-tree with GitOps**, per [ADR-0201](0201-gitops.md). Admission policy is files in the repo, per principle 1 of [ADR-0000](0000-platform-foundations.md).
5. **The trust root survives a forge migration**, per [ADR-0102](0102-source-control-and-ci.md). A change in the middle of its life means re-signing every image, or keeping two verification paths for good.

## Considered options

### Signing

| Option | Where trust is rooted | Key custody | Verdict |
| --- | --- | --- | --- |
| **cosign with a key pair in SOPS** | **the own age key of the cluster**, per [ADR-0202](0202-secrets.md) | one key pair, in the secret machinery that already holds every other secret | **Chosen.** The only option whose trust root is inside the boundary that principle 3 draws *(reasoned)* |
| cosign keyless against the public Fulcio and Rekor | the certificate authority and transparency log of a third party | none | Its value is verification by parties who do not trust us. The only verifier here is our own admission controller. It also outsources the trust root. [ADR-0102](0102-source-control-and-ci.md) rejects a managed forge for that same dependency. The public instance signs only for issuers named in [its own configuration](https://docs.sigstore.dev/certificate_authority/oidc-in-fulcio/). So the issuer of a self-hosted forge must be reachable from the internet and accepted upstream before it can sign at all |
| cosign keyless against a self-hosted Fulcio and Rekor | a certificate authority we operate | **a CA root key.** This is more consequential than a signing key. [The backends of Fulcio](https://github.com/sigstore/fulcio/blob/main/docs/setup.md) include an on-disk encrypted key, so it can sit in the same machinery | Custody is solvable. The floor is not. Fulcio, Rekor, TUF root metadata, and a timestamp authority join the always-on floor. They serve a single verifier that already trusts us. Principle 2 refuses the purchase |
| notation, from the Notary Project | a key or a hosted trust store | the same as the chosen option | Equivalent custody, with a narrower ecosystem and tooling |
| A detached GPG signature beside the image | a key we hold | the same as the chosen option | Not an OCI artefact. Nothing publishes it as a referrer, and no admission controller on this floor reads one. So the verification step that this table exists to enable has nothing to call |
| No signing, digest pins only | nothing | none | Digest pins prove immutability, not origin. A pinned digest from a compromised builder is still pinned |

**Keyless is a technology for axis B low.** It works by trusting somebody else to attest who the signer is. Its payoff is a public, tamper-evident log that a stranger can check without the help of the signer. This platform has no such audience. That is the *signal with no reader* of [ADR-0000](0000-platform-foundations.md), applied to a signature. [ADR-0103](0103-release-and-versioning.md) applies it to a version number in the same way. The reader is named, and here nobody stands in that position.

### Admission enforcement

| Option | Added components | Policy as files | Verifies signatures at admission | Verdict |
| --- | --- | --- | --- | --- |
| **Kyverno** | one controller | YAML in the repo | yes, natively, including attestations | **Chosen.** The policy language is the same YAML as the rest of the platform *(documented)* |
| OPA Gatekeeper | one controller | Rego in the repo | through an external data provider | Rego is a second language for one concern |
| Ratify with Gatekeeper | two | Rego plus verifier CRDs | yes, as an external verifier | Purpose-built for exactly this. It costs the second language of Gatekeeper *and* a second component |
| Kubernetes `ValidatingAdmissionPolicy` | **none, because it is in-tree** | CEL in the repo | no, because a CEL expression cannot read a registry | The option that expands no floor. Signature verification is the one thing that in-process CEL cannot do |
| Admission in CI only | none | not applicable | no, because the pipeline is the gate | The deploying party owns the pipeline, so driver 3 rules it out |

### Scanning and SBOM generation

Both are Tier 2, per [ADR-0002](0002-tool-adoption.md). Each reads an image and writes a report. So a swap changes a task and leaves the artefacts alone.

| Concern | Chosen | Picked over | Why |
| --- | --- | --- | --- |
| Vulnerability scanning | **Trivy** | Grype, Clair, a registry-side scanner, Snyk | One binary covers OS packages, language dependencies, infrastructure-as-code, and secrets. So one gate covers surfaces that would otherwise need several. Grype is the closest, and it scans packages only. A registry-side scanner runs after the push, which is after the merge that this gates *(reasoned)* |
| SBOM generation | **syft** | the own SBOM output of Trivy, cdxgen, the SBOM of the build system | It produces the SPDX document that the attestation carries, and the scanner also reads its output. If the scanner did both, the fidelity of the SBOM would depend on the release cadence of a scanner |

**Trivy works at push time, and that is a property, not a defect.** It sees what is being built. Nothing here notices that a CVE published today affects an image built months ago. That is the pull-time half. It is the Dependency-Track row of [`../operational-surface.md`](../operational-surface.md), deferred on the operational budget, with its triggers stated there.

## Decision

| Concern | Decision |
| --- | --- |
| Image signing | **cosign with a key pair**, generated at bootstrap and held in SOPS, per [ADR-0202](0202-secrets.md). Every first-party image is signed |
| SBOM | generated with **syft** in [SPDX](https://spdx.dev/) form, and attached as a cosign attestation. So the bill of materials travels with the image |
| Provenance | **[SLSA](https://slsa.dev/) build provenance**: what source and what builder. It is emitted as an [in-toto](https://github.com/in-toto/attestation) attestation, the envelope that SLSA and cosign both speak |
| Admission | **Kyverno** verifies the signature and the required attestations on first-party images. It also requires digest-pinned references |
| Third-party images | pinned by digest and allow-listed. Upstream signatures are verified where the publisher provides them. Where it does not, a pinned digest is accepted |
| Vulnerability scanning | **in CI, where a finding blocks a merge.** The registry does not scan, per [ADR-0105](0105-image-registry.md), and the cluster does not scan |

Signatures and attestations are OCI referrers, stored beside the image in the registry of [ADR-0105](0105-image-registry.md). So admission verification is a registry read.

**Signing, SBOM, and provenance happen at build time. Kyverno is the runtime gate.** Scanning belongs to the build-time half for the same reason. A scan after admission reports on what already shipped, so it is a dashboard, not a gate. Each instance chooses its scanner, and [`per-instance-hardening.md`](../reference/per-instance-hardening.md) records that choice. The rule that the scan runs before merge is not a choice.

**There is one signing identity, and the forge migration does not change it.** The private key is a SOPS-encrypted secret that the CI job decrypts. The public key is committed, and the Kyverno policy names it. Nothing about it depends on which forge runs the pipeline. So a forge move re-targets the workflow and leaves the trust root untouched, as driver 5 requires.

**Escape hatch.** First-party images can be published for consumers outside this organisation to pull and verify. Then public verifiability has a reader, and keyless earns its cost.

| Field | Value |
| --- | --- |
| **Trigger** | a first-party image is published for an external party to verify |
| **Seam** | present. cosign signs and Kyverno verifies in both cases, so the change is which key material the policy names |
| **Cost if adopted late** | images already published carry a signature that only our key can verify. So external verification starts at the switch, and does not cover history |

The digest-pin rule supports [ADR-0103](0103-release-and-versioning.md). Production already pins by digest, and Kyverno makes that structural, not only a convention.

## Consequences

### Positive

- The cluster runs only images that it can prove came from our pipeline. The digest-pin rule closes tag drift.
- The trust root is inside the sovereignty boundary. Nothing outside the organisation is asked to vouch for what we built.
- SBOM and provenance make incident response and CVE triage a lookup, not an investigation.

### Negative and Risks

- **Kyverno is a new Core component**, with the operational surface of an admission controller. This is accepted: it is the enforcement point that makes the rest mandatory.
- **This decision pins the signing tool to a major version, not inertia.** cosign 3 makes the Sigstore bundle format mandatory. The only path that verifies a bundle initialises the public Sigstore TUF root before it reads the key. That puts `tuf-repo-cdn.sigstore.dev` in the path of every admission. That is the third-party trust root that this decision refused. The pin is reviewed again when a bundle can be verified against a bare public key with no trust-root fetch. `(ref: cosign 3 --new-bundle-format; Kyverno verifyImages type: SigstoreBundle)`
- **There is a key, and a key can be stolen.** A compromised signing key signs anything, and no independent log contradicts it. Keyless buys that property, and this option does not. Three things limit the risk: the key never leaves SOPS and the cluster, rotation is a documented procedure and not an improvisation, and Kyverno pins the public key. So a substituted key fails admission and does not pass quietly.
- **Signature history is only as good as the history of the key.** Rotation invalidates nothing already signed. So the policy carries the current and the previous public keys through a rotation window.
- **An admission gate can block a deploy during an incident.** [`docs/guide/break-glass.md`](../guide/break-glass.md) documents the break-glass path, so nobody improvises it.

## Rules

- CI cosign-signs every first-party image with the platform key pair. Every first-party image carries an SBOM and a provenance attestation. `(CI: ci:sign)`
- Vulnerability scanning is a merge gate in CI. Neither the registry nor the cluster scans, per [ADR-0105](0105-image-registry.md).
- The signing private key exists only as a SOPS-encrypted secret, and only CI decrypts it. The public key is committed, and the Kyverno policy names it. The private key is never held by a person and never stored unencrypted. There is one platform key pair, not one per environment, because an image is built once and the same digest goes through every environment.
- Kyverno rejects at admission any image that lacks a valid signature or is referenced by a floating tag. `(enforced: Kyverno)`
- All images are digest-pinned. `(CI: lint:floating-tags; enforced: Kyverno)`
- Third-party images are pinned by digest and allow-listed. Upstream signatures are verified where the publisher provides them. `(CI: lint:image-allowlist; enforced: Kyverno)`
- Admission policy is committed YAML that Argo CD reconciles, never applied by hand.
