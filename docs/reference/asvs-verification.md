# ASVS Verification

[ADR-0304](../adr/0304-identity-and-authorization.md) sets the application security bar at OWASP ASVS Level 2. It states that this is a design claim and not a test result. This table is where someone examines that claim. It has one row per concern, the ADR that owns the concern, and the verdict from the last examination.

**A verdict has one of three values:**

- *Met*: someone read the requirements against the implementation and found that they hold.
- *Met with exception*: a requirement is unmet on purpose, and the owning ADR records the reason.
- *Unverified*: nobody has looked. Every row starts in this state. A row also returns to it when a full cadence passes with no examination.

**Cadence, and who walks it.** A walk happens once per ASVS release, and on any change to a row's owning ADR. The verdict belongs to a document version and to an implementation, so the row names both.

The walk is scheduled and assigned. It does not wait for someone to start it. It uses the quarterly `Schedule` that [`upstream-status.md`](upstream-status.md) describes. That `Schedule` opens one tracking issue with three sets of rows:

- the rows of this table
- the rows of [`upstream-status.md`](upstream-status.md)
- the **query** rows of [`deferral-register.md`](deferral-register.md)

A row's owner is the owner of its owning ADR.

**Every row starts at *unverified*, and this shows the table works correctly.** [ADR-0304](../adr/0304-identity-and-authorization.md) says the ASVS bar is a design claim that nobody has examined. The third verdict exists to record this honestly. The table fails only when it shows *met* for a row that nobody walked.

**A first walk is a full pass. It is different work from the cadence that follows.** A project chooses one of two ways to do it. The template does not choose:

| Way | Cost | Result |
| --- | --- | --- |
| Read the checklist against the implementation in-house | the reader's time | verdicts that a maintainer can act on directly |
| Commission a third-party assessment | money | verdicts with an auditor's name on them |

The second way is worth its price only where an outside party must believe the result. The cost of both ways grows with every ADR that cites the bar. So a project that plans to make the claim does the first walk early.

| Concern | Owner | Verdict | Examined |
| --- | --- | --- | --- |
| Authentication | [ADR-0304](../adr/0304-identity-and-authorization.md): Kratos sessions, the password policy shaped on NIST 800-63B, AAL levels | unverified | never |
| Session management | [ADR-0304](../adr/0304-identity-and-authorization.md), [ADR-0306](../adr/0306-trust-tiers-and-urls.md): lifetimes, step-up, cookie scope | unverified | never |
| Access control | [ADR-0304](../adr/0304-identity-and-authorization.md): OpenFGA through `Checker`, never inline | unverified | never |
| Input validation and encoding | [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md): validators compiled into the decoder from the spec | unverified | never |
| Error handling and logging | [ADR-0303](../adr/0303-api-contracts-and-lifecycle.md)'s error envelope, [ADR-0500](../adr/0500-observability.md)'s structured logs and PII rule | unverified | never |
| Data protection and privacy | [ADR-0301](../adr/0301-data-lifecycle-privacy.md) | unverified | never |
| Communications security | [ADR-0206](../adr/0206-cluster-networking.md) east-west encryption, [ADR-0205](../adr/0205-environment-parity.md) verified TLS in every environment | unverified | never |
| Configuration and secrets | [ADR-0202](../adr/0202-secrets.md) | unverified | never |
| Malicious code and supply chain | [ADR-0104](../adr/0104-supply-chain-security.md) | unverified | never |

## Two things this table is not

**It is not a compliance artefact.** ASVS is the bar that this platform designs to. A framework that a project must prove it meets goes in [`per-instance-hardening.md`](per-instance-hardening.md).

**It does not cover vendored surfaces.** Lowdefy, Grafana, and pgweb are outside the bar, per [ADR-0304](../adr/0304-identity-and-authorization.md). [ADR-0400](../adr/0400-frontend.md) draws the same boundary for accessibility. The platform cannot keep a claim about software that it does not write.
