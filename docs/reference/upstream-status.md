# Upstream Status

The ADR set rests on third-party facts that can become false with no change in this repository. Examples are a project's maintenance status, a licence, a governance body, and a capability's availability tier. These facts are live state. So they live here and not in the ADRs that cite them. Each row carries the date of its last verification.

**A stale row is a decision that rests on something nobody has checked.** A row that nobody verifies for a year is marked unverified again. It does not stay and suggest that it is current.

**The cadence has an owner, because a cadence without an owner is a signal with no reader,** per [ADR-0000](../adr/0000-platform-foundations.md). A quarterly Temporal `Schedule` opens a tracking issue in the forge. The issue goes to the platform component owner of the ADR that the row is load-bearing for. [`../operational-surface.md`](../operational-surface.md) names that owner. The same `Schedule` also carries two other sets of rows, where this set asks someone to go and look:

- the rows of [`asvs-verification.md`](asvs-verification.md)
- the **query** rows of [`deferral-register.md`](deferral-register.md)

So there is one issue, three tables, and one owner per row.

To walk a row, do three steps:

1. Read the upstream source.
2. Set the *Verified* date to today, whether the status changed or not.
3. If the status changed, open a second issue against the owning ADR. Do not edit the ADR from here.

The date change is the evidence that the check happened. A status change is a decision to reopen.

| Fact | Status | Verified | Load-bearing for |
| --- | --- | --- | --- |
| Grafana OnCall's open-source distribution | entered maintenance in March 2025 and was archived in March 2026. The repository is read-only. Cloud-connected phone, SMS, and push delivery are withdrawn from OSS | 2026-08-11 | [ADR-0502](../adr/0502-alerting-and-on-call.md): the direct evidence that no credible self-hosted escalation layer exists. Also [ADR-0000](../adr/0000-platform-foundations.md)'s ranking of on-call as the second thing to concede |
| Temporal's Rust SDK | public preview, not generally available | 2026-08-11 | [ADR-0100](../adr/0100-language-and-runtime.md): driver 4 excludes Rust on SDK maturity, and this fact is the reason |
| OpenTelemetry Rust | beta across all three signals | 2026-08-11 | [ADR-0100](../adr/0100-language-and-runtime.md), the same driver |
| zot's OCI 1.1 referrers support | native, so signatures and attestations are stored next to the image with no workaround | 2026-08-11 | [ADR-0105](../adr/0105-image-registry.md), [ADR-0104](../adr/0104-supply-chain-security.md): admission verification is a registry read |
| MinIO's community edition | the repository was archived in April 2026. Distribution is source-only, and the maintained build is a product with a proprietary licence | 2026-08-11 | [ADR-0207](../adr/0207-cluster-storage.md): the object store is not MinIO because of abandonment, not novelty |
| Forgejo's governance | a non-profit umbrella, GPLv3-or-later | 2026-08-11 | [ADR-0102](../adr/0102-source-control-and-ci.md): this is the only row that separates it from Gitea, so it carries the decision alone |
| Calico's open distribution | FQDN egress policy and per-flow logs stay in the paid tier | 2026-08-11 | [ADR-0206](../adr/0206-cluster-networking.md): both capabilities are load-bearing, so Calico is the runner-up and not the choice |
| Distroless base images | tags that are not current stop getting updates | 2026-08-11 | [ADR-0101](../adr/0101-monorepo.md): a base image left on an old tag is a security decision made by not deciding |
| The licence and governing-body columns of the tool register | read from each project's own `LICENSE` file. For the CNCF rows, also read from the [landscape data](https://github.com/cncf/landscape) | 2026-08-13 | [ADR-0002](../adr/0002-tool-adoption.md): the columns are evidence about exit cost, and a cell that nobody read is not evidence |
| Prism's `--multiprocess` flag | defaults to `true`, and `stoplight/prism:5.15.10` crashes on startup with it. `createMultiProcessPrism` reads `cluster.isPrimary` from an undefined import | 2026-08-14 | [ADR-0600](../adr/0600-local-development-loop.md): the mock runs with the flag off. The flag gives log throughput that this loop does not need, so check again only on a version bump |
| shadcn/ui's `radix-nova` style | its stylesheet is imported from the `shadcn` package and not copied into the repository. So the CLI is a build input and not only a generator | 2026-09-19 | [ADR-0400](../adr/0400-frontend.md): the package is a devDependency, and the build resolves the import. A style that copies its own CSS would drop the dependency |
| shadcn/ui's default `--input`, `--ring`, and `--muted-foreground` | below WCAG 2.2 AA against the page in the neutral base: 1.26:1, 2.59:1, and 4.02:1 | 2026-09-19 | [ADR-0400](../adr/0400-frontend.md): `theme.css` darkens the three, and `lint:contrast` holds them. Check again on a style bump |

## What belongs here

A fact belongs in this table when **someone else can change it**. A fact belongs in an ADR when this platform decides it.

| Kind | Where |
| --- | --- |
| Maintenance status, archival, abandonment | here |
| Licence, governance body, ownership change | here |
| A capability that moves between free and paid tiers | here |
| A capability's availability tier: preview, beta, or GA | here |
| What this platform does about any of the above | the owning ADR |

No reasoning cites this document. A decision cites the fact, and this document verifies the fact. If the fact changes, the decision's own trigger reopens it. An edit to this table does not.
