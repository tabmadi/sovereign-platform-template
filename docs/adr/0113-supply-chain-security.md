# ADR-0113: Supply-Chain Security

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0116](0116-forge-and-pipelines.md), [ADR-0112](0112-release-and-versioning.md), [ADR-0114](0114-image-registry.md), [ADR-0201](0201-gitops.md), [ADR-0203](0203-policy-enforcement.md), [ADR-0701](0701-product-design-and-discovery.md)
- **Decides:** Images are signed by a cosign key pair held in SOPS, carry syft SBOM and SLSA provenance attestations, and are verified at admission.

## Context

The platform runs first-party images built in CI, plus third-party charts and images. With no control, the provenance of a running image is inferred from the registry it came from. A registry records where a thing was found, not who made it.

The platform team is small compared with the whole fleet, per [ADR-0000](0000-platform-foundations.md). It also grows much more slowly than the fleet. So CI must apply the controls by default, and admission must enforce them. A manual audit does not scale and does not block.

## Decision drivers

1. **The origin of a running image is verifiable.** It is not inferred from where the image was found.
2. **No hardware custody and no credential held by a human.** A team this size cannot operate an HSM. A key that a person can copy is not a signing identity. The key must sit in machinery that the platform already runs.
3. **A control that the constrained party can bypass is not a control.** The gate for an image must sit where the deploying party cannot route around it.
4. **In-tree with GitOps**, per [ADR-0201](0201-gitops.md). Admission policy is files in the repo, per principle 1 of [ADR-0000](0000-platform-foundations.md).
5. **The trust root survives a forge migration**, per [ADR-0116](0116-forge-and-pipelines.md). A change in the middle of its life means re-signing every image, or keeping two verification paths for good.

## Considered options

### Signing

| Option | 1 Verifiable origin | 2 No hardware, no human key | 5 Survives a forge move | Floor added | Verdict |
| --- | --- | --- | --- | --- | --- |
| **cosign with a key pair in SOPS** | **Yes** | **Yes. The private half is a SOPS secret that only CI decrypts, per [ADR-0202](0202-secrets.md)** | **Yes. The key does not depend on the forge** | **None** | **Chosen** |
| cosign keyless against the public Fulcio and Rekor | Yes | Yes | No. Fulcio signs only for OIDC issuers in its own configuration, so a self-hosted forge must be accepted upstream | None, and a third party holds the trust root | Rejected on driver 5 and principle 3 |
| cosign keyless against a self-hosted Fulcio and Rekor | Yes | A CA root key, which can sit in the same machinery | Yes | Fulcio, Rekor, TUF metadata, and a timestamp authority, for one verifier | Rejected on principle 2 |
| notation, from the Notary Project | Yes | Yes, with a key in the same machinery | Yes | None | Rejected. Kyverno verifies both, and the tooling around cosign is wider. It is the runner-up |
| A detached GPG signature beside the image | Not at admission. It is not an OCI referrer | Yes | Yes | None | Rejected on driver 1 |
| No signing, digest pins only | No. A pin proves immutability, not origin | Yes | Yes | None | Rejected on driver 1 |

Sources:

- Signing with a key pair: [Sigstore docs, signing with self-managed keys](https://docs.sigstore.dev/cosign/key_management/overview/).
- The OIDC issuers that the public Fulcio accepts: [Sigstore docs, OIDC in Fulcio](https://docs.sigstore.dev/certificate_authority/oidc-in-fulcio/).
- The services of a self-hosted Sigstore: [Fulcio setup](https://github.com/sigstore/fulcio/blob/main/docs/setup.md).
- Kyverno verifies cosign and notation signatures: [Kyverno docs, verify images](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/).

**Keyless is a technology for axis B low.** It works by trusting somebody else to attest who the signer is. Its payoff is a public, tamper-evident log that a stranger can check without the help of the signer. This platform has no such audience. That is the *signal with no reader* of [ADR-0000](0000-platform-foundations.md), applied to a signature. [ADR-0112](0112-release-and-versioning.md) applies it to a version number in the same way. The reader is named, and here nobody stands in that position.

### Admission enforcement

| Option | 1 Verifiable origin at admission | 3 Not bypassable by the deployer | 4 Policy as files | Floor added | Verdict |
| --- | --- | --- | --- | --- | --- |
| **Kyverno** | **Yes, signatures and attestations, natively** | **Yes. It is an admission webhook** | **Yes, YAML** | **One controller** | **Chosen** |
| OPA Gatekeeper | Only through an external data provider | Yes | Yes, Rego | One controller and a second policy language | Rejected on driver 1 |
| Ratify with Gatekeeper | Yes, as an external verifier | Yes | Yes, Rego and verifier CRDs | Two components and a second language | Rejected on principle 2 |
| Kubernetes `ValidatingAdmissionPolicy` | No. A CEL expression cannot read a registry | Yes | Yes, CEL | None | Rejected on driver 1 |
| Checks in CI only | Yes, in the pipeline | No. The deploying party owns the pipeline | Yes | None | Rejected on driver 3 |

Sources:

- Kyverno image verification: [Kyverno docs, verify images](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/).
- Gatekeeper reads outside data through providers: [Gatekeeper docs, external data](https://open-policy-agent.github.io/gatekeeper/website/docs/externaldata/).
- Ratify as a Gatekeeper verifier: [Ratify](https://ratify.dev/).
- CEL admission policies run in the API server with no outside calls: [Kubernetes docs, ValidatingAdmissionPolicy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/).

### Scanning and SBOM generation

Both are Tier 2, per [ADR-0002](0002-tool-adoption.md). Each reads an image and writes a report. So a swap changes a task and leaves the artefacts alone.

| Concern | Chosen | Picked over | Why |
| --- | --- | --- | --- |
| Vulnerability scanning | **Trivy** | Grype, Clair, a registry-side scanner, Snyk | One binary covers OS packages, language dependencies, infrastructure-as-code, and secrets. So one gate covers surfaces that would otherwise need several. Grype is the closest, and it scans packages only. A registry-side scanner runs after the push, which is after the merge that this gates *(reasoned)* |
| SBOM generation | **syft** | the own SBOM output of Trivy, cdxgen, the SBOM of the build system | It produces the SPDX document that the attestation carries, and the scanner also reads its output. If the scanner did both, the fidelity of the SBOM would depend on the release cadence of a scanner |

Sources:

- What Trivy scans: [Trivy docs, scanners](https://trivy.dev/latest/docs/scanner/vulnerability/).
- What Grype scans: [Grype](https://github.com/anchore/grype).
- syft writes SPDX and CycloneDX: [syft](https://github.com/anchore/syft).

**Trivy works at push time, and that is a property, not a defect.** It sees what is being built. Nothing here notices that a CVE published today affects an image built months ago. That is the pull-time half. It is the Dependency-Track row of [`../operational-surface.md`](../operational-surface.md), deferred on the operational budget, with its triggers stated there.

## Decision

| Concern | Decision |
| --- | --- |
| Image signing | **cosign with a key pair**, generated at bootstrap and held in SOPS, per [ADR-0202](0202-secrets.md). Every first-party image is signed |
| SBOM | generated with **syft** in [SPDX](https://spdx.dev/) form, and attached as a cosign attestation. So the bill of materials travels with the image |
| Provenance | **[SLSA](https://slsa.dev/) build provenance**: what source and what builder. It is emitted as an [in-toto](https://github.com/in-toto/attestation) attestation, the envelope that SLSA and cosign both speak |
| Admission | **Kyverno** verifies the signature and the required attestations on first-party images. It also requires digest-pinned references |
| Third-party images | pinned by digest and allow-listed. Upstream signatures are verified where the publisher provides them. Where it does not, a pinned digest is accepted |
| Vulnerability scanning | **in CI, where a finding blocks a merge.** The registry does not scan, per [ADR-0114](0114-image-registry.md), and the cluster does not scan |

Signatures and attestations are OCI referrers, stored beside the image in the registry of [ADR-0114](0114-image-registry.md). So admission verification is a registry read.

**Signing, SBOM, and provenance happen at build time. Kyverno is the runtime gate.** Scanning belongs to the build-time half for the same reason. A scan after admission reports on what already shipped, so it is a dashboard, not a gate. Each instance chooses its scanner, and [`per-instance-hardening.md`](../reference/per-instance-hardening.md) records that choice. The rule that the scan runs before merge is not a choice.

**There is one signing identity, and the forge migration does not change it.** The private key is a SOPS-encrypted secret that the CI job decrypts. The public key is committed, and the Kyverno policy names it. Nothing about it depends on which forge runs the pipeline. So a forge move re-targets the workflow and leaves the trust root untouched, as driver 5 requires.

**Escape hatch.** First-party images can be published for consumers outside this organisation to pull and verify. Then public verifiability has a reader, and keyless earns its cost.

| Field | Value |
| --- | --- |
| **Trigger** | a first-party image is published for an external party to verify |
| **Seam** | present. cosign signs and Kyverno verifies in both cases, so the change is which key material the policy names |
| **Cost if adopted late** | images already published carry a signature that only our key can verify. So external verification starts at the switch, and does not cover history |

The digest-pin rule supports [ADR-0112](0112-release-and-versioning.md). Production already pins by digest, and Kyverno makes that structural, not only a convention.

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

- CI cosign-signs every first-party image with the platform key pair. Every first-party image carries an SBOM and a provenance attestation. `(CI: ci-sign)`
- Commits are signed by a different mechanism. [ADR-0116](0116-forge-and-pipelines.md) holds the rule. The cosign key signs images only.
- Vulnerability scanning is a merge gate in CI. Neither the registry nor the cluster scans, per [ADR-0114](0114-image-registry.md).
- The signing private key exists only as a SOPS-encrypted secret, and only CI decrypts it. The public key is committed, and the Kyverno policy names it. The private key is never held by a person and never stored unencrypted. There is one platform key pair, not one per environment, because an image is built once and the same digest goes through every environment.
- Kyverno rejects at admission any image that lacks a valid signature or is referenced by a floating tag. `(enforced: Kyverno)`
- All images are digest-pinned. `(CI: lint-floating-tags; enforced: Kyverno)`
- The one exception is the design image of [ADR-0701](0701-product-design-and-discovery.md). Its manifest names the commit tag `pr-<n>-<sha>`, and admission verifies its signature and pins the pod to that digest. `(enforced: Kyverno)`
- A `design/` image runs only in a `design-pr-<n>` namespace. `(enforced: Kyverno)`
- Third-party images are pinned by digest and allow-listed. Upstream signatures are verified where the publisher provides them. `(CI: lint-image-allowlist; enforced: Kyverno)`
- Admission policy is committed YAML that Argo CD reconciles, never applied by hand.
