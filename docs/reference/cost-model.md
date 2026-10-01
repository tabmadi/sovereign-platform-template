# Cost Model

**Fee predictability** is part of the case for sovereignty, per [ADR-0000](../adr/0000-platform-foundations.md) principle 3. No document states what this claim means. This document does, with no prices. A price list is wrong within a year. It is also wrong for every adopter except the one who wrote it.

The platform knows the **shape of the bill** and the items on it. A project knows its provider and its scale. Together the two give a number. Neither gives one alone. [`../operational-surface.md`](../operational-surface.md) uses the same division for capacity, for the same reason.

## The claim, stated precisely

The claim is not that self-hosting is cheaper. The claim is that its cost curve has a different shape, and the project buys that shape.

| | Self-hosted here | Managed equivalents |
| --- | --- | --- |
| **Floor** | high, and paid from day one. The platform runs before any service does | low, often near zero |
| **Slope against usage** | flat between node boundaries. Requests, tenants, and services add no cost until capacity does | follows usage. Per-seat or per-service fees follow the size of the organisation |
| **Steps** | at node boundaries, and each step is a known quantity | none visible. This is the appeal and also the exposure |
| **Predictability** | a change in the bill is a change that someone made on purpose | a change in the bill can come from traffic, from a vendor's pricing, or from a tier's definition |
| **The bad surprise** | capacity runs out under load, which is an incident | a bill arrives that nobody decided, which is a negotiation |

**The trade is a known cost against an unknown one.** At axis B maximal, this trade is the purpose. A fixed floor is a number to plan against. A bill that follows usage is a number to react to. Where a project cannot afford the floor, the answer is [`../adoption-path.md`](../adoption-path.md), not a cheaper reading of this document.

## What appears on the bill

This is the inventory to price against a provider. Multiply each row by the number of environments, except where a row says otherwise. The template assumes dev, staging, and production, per [ADR-0205](../adr/0205-environment-parity.md).

| Line item | Driven by | Notes |
| --- | --- | --- |
| Compute instances | node count per cluster | etcd quorum sets the control plane's minimum, which is three. This is a threshold, not a price, per [ADR-0200](../adr/0200-cluster-topology.md) |
| Node disk | the working set of every stateful component, plus local volumes | volumes are node-local, so disk is sized per node and not pooled, per [ADR-0200](../adr/0200-cluster-topology.md) |
| Load balancer | one per cluster | |
| Object storage capacity | backups, logs, traces, profiles, and images, each against its retention | the largest variable row. Retention policy controls it directly, per [ADR-0500](../adr/0500-observability.md) |
| Object storage requests and egress | telemetry write rate, image pulls, restore reads | follows usage even here. Teams forget this row most often |
| Object storage, production | runs outside the cluster | a host or a service. It is not optional: it holds the backups that a rebuild reads |
| Static IP for mail | one, dedicated, with a matching `PTR` | separate from the cluster's ingress address, per [ADR-0307](../adr/0307-outbound-email.md) |
| DNS zone | one per environment domain | |
| Certificates | none, because of ACME | a cost avoided, and the reason cert-manager is on the floor |
| Forge and CI runners | pipeline minutes become instance hours on infrastructure you own | self-hosted CI turns a per-minute fee into capacity, per [ADR-0102](../adr/0102-source-control-and-ci.md) |
| Backup storage and retention | the recovery objective, and Object Lock retention no shorter than it | |
| Paging service | the escalation concession, when the trigger fires | the one managed subscription that the template expects, per [ADR-0502](../adr/0502-alerting-and-on-call.md) |

**What is not on the bill.** Every per-seat fee for the tools that this floor replaces:

- the forge
- the registry
- the observability backend
- the error tracker
- the workflow engine
- the identity provider

Sovereignty removes these fees, and they are the honest other side of the floor. A comparison that prices the floor and leaves them out is not a comparison.

## The row that is not infrastructure

**Operator attention is the scarce resource, and it is the largest line item.** [`../operational-surface.md`](../operational-surface.md) lists the recurring obligation and the failure-response requirement of every component. Those columns are the labour half of this bill. A cost model can price instances and leave these columns out. Sovereignty then looks cheapest exactly where it costs the most: a small team, few services, and the same fixed floor.

The useful ratio is not cost per month. It is **platform work against product work**. With many services the ratio is comfortable. With a handful of services it comes close to one to one, per [ADR-0000](../adr/0000-platform-foundations.md). Fewer services make the platform heavier in proportion, and no infrastructure line item shows this.

## Using this

1. Price the inventory above with your provider, for each environment.
2. Add the removed per-seat fees as a credit, honestly. Include the ones that a smaller team would not have bought.
3. Add up the obligation columns in [`../operational-surface.md`](../operational-surface.md) against your own coverage hours.
4. Compare against [`../adoption-path.md`](../adoption-path.md) Band 2. It is ranked by **capacity returned per unit of sovereignty conceded**. This is the same unit as step 3, not step 1.

The answer is usually in steps 3 and 4. A project that cannot afford the floor can usually afford the instances.
