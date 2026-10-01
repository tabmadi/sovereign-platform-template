# Per-Instance Hardening and Compliance

[`security-baseline.md`](../security-baseline.md) is the floor that every project inherits. It is generated from the Rules sections that own each control. This document is the other half. It lists what a **particular** project turns on for its own risk profile or its own compliance framework.

This document is written by hand and not generated, because its subject is the instance and not the template. Nothing here is a gap in the baseline. Each row is a control that the template does not impose on every project. The row also names the condition that makes the control necessary.

## Conscious omissions from the baseline

Each row is a values change or a policy change that a project makes when the condition holds.

| Omitted | Why it is not a default | Turn it on when |
| --- | --- | --- |
| **Per-account lockout and CAPTCHA** | The edge IP rate limit covers the untargeted case. Per-account backoff punishes the attacked account as much as the attacker, per [ADR-0304](../adr/0304-identity-and-authorization.md) | Credential stuffing targets named accounts, or the product's user base makes an account takeover much worse than a lockout |
| **The HaveIBeenPwned breach check** | Its client ignores network errors by default. So on a default-deny cluster it fails open silently, and registration pays a latency cost for a check that did not run, per [ADR-0304](../adr/0304-identity-and-authorization.md) | The egress allowance for it exists and is verified. A control that looks enabled and does nothing on the wire is worse than one that is honestly off |
| **Ops-tier token isolation** | The parent-scoped session cookie is accepted while every origin under the host is first-party and gated at the edge, per [ADR-0306](../adr/0306-trust-tiers-and-urls.md) | The product surface shows content from one user to another, or the apex hosts anything that is not first-party. [`adoption-path.md`](../adoption-path.md) ranks the two forms |
| **`__Secure-` cookie prefix** | A rename of the session cookie touches Kratos, the Oathkeeper rule set, and the frontend proxy together. The prefix adds no isolation that the `Secure` attribute does not already give | The cookie is renamed for another reason. `__Host-` stays inapplicable, because it forbids the `Domain` attribute that the tier model requires |
| **B2C MFA, social login, SCIM** | Each is a product decision and not a platform decision, per [ADR-0304](../adr/0304-identity-and-authorization.md) | The product requires it. Operator AAL2 is baseline in both cases |
| **Per-workload certificate identity** | Positional trust is the recorded deviation from NIST SP 800-207. Default-deny and the `restricted` profile limit it, per [ADR-0305](../adr/0305-edge-auth-and-traffic-policy.md) | A service performs a monetary mutation, a second team owns a service, or an auditor requires a CA chain |

## Which scanner an instance runs

[ADR-0104](../adr/0104-supply-chain-security.md) makes vulnerability scanning a merge gate and leaves the choice of scanner to the instance. This document records the choice, with its ignore policy and its failure threshold. A reviewer needs these parts, and neither is a property of the template.

## Reaching a named compliance framework

A project reaches a framework by adding layers on top of the baseline, with no fork of the template. Each row is a values overlay, a policy change, or a CI addition.

| Requirement | Where it lands |
| --- | --- |
| Audit retention over the framework's window | the per-environment observability values. The authorization decision events already go to the log store, per [ADR-0500](../adr/0500-observability.md) |
| Network segmentation beyond default-deny | tighter CiliumNetworkPolicy per namespace for the regulated data path, per [ADR-0206](../adr/0206-cluster-networking.md) |
| Encryption at rest | the storage class and the database values in the per-environment infrastructure. The template is provider-agnostic and states no default |
| Stronger authentication | required MFA, shorter session lifetimes, and the ops-tier token isolation above |
| Periodic access review | a scheduled review of the operator group and the dashboard relations. OpenFGA holds them as the source of truth, per [ADR-0304](../adr/0304-identity-and-authorization.md) |
| Vulnerability management with provable continuity | a scanner's findings are a merge gate. Continuous triage across the fleet against images already built needs a component that this platform does not run, per [`operational-surface.md`](../operational-surface.md) |
| Penetration-test attestation | a CI artefact and a schedule. Nothing in the template changes |

**PCI DSS depends on scope. It is not a layer.** The platform stores no cardholder data, and a payment integration hands off to a provider. A project that takes card data directly brings the scope with it. That changes [ADR-0300](../adr/0300-data.md) and [ADR-0301](../adr/0301-data-lifecycle-privacy.md), not this document, per [ADR-0000](../adr/0000-platform-foundations.md).

## The verification obligation

A control that is claimed and never examined becomes, over time, a control that people only believe in. [ADR-0304](../adr/0304-identity-and-authorization.md) sets the ASVS bar and the cadence. [`asvs-verification.md`](asvs-verification.md) holds the per-row verdicts and the date of each last examination. A row in this document that a project turns on joins that table. Hardening that nobody verifies is the same claim as a baseline control that nobody verifies.
