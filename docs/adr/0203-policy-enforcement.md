# ADR-0203: Policy Enforcement Strategy

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0001](0001-documentation-and-output-conventions.md), [ADR-0101](0101-monorepo.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0202](0202-secrets.md), [ADR-0204](0204-resource-management.md), [ADR-0303](0303-api-contracts-and-lifecycle.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md)
- **Decides:** Each invariant is enforced at the earliest layer that the constrained party cannot bypass, with one layer per class of invariant.

## Context

Four mechanisms enforce invariants on this platform:

- CI lints, before merge.
- Pod Security Admission, in the API server.
- Kyverno, at admission.
- CiliumNetworkPolicy, in the datapath.

The ADR that needed each mechanism decides it. Each of those ADRs answers how to enforce its own rule. None answers which layer may enforce which class of rule.

That gap has two failure modes:

- An invariant lands in the wrong layer. For example, CI checks a runtime property only before merge, so anything that reaches the cluster by another path is unchecked.
- An invariant lands in two layers. The second copy drifts from the first until they disagree, and nobody trusts either.

This ADR decides the assignment and the rule that produces it. It adds no mechanism and decides none again. The ADR that introduced each mechanism owns what that mechanism does.

## Decision drivers

1. **One enforcement point per invariant**, per principle 5 of [ADR-0000](0000-platform-foundations.md). A rule checked in two places is two rules. They agree until they do not.
2. **Enforcement sits where the constrained party cannot go around it**, per [ADR-0104](0104-supply-chain-security.md). A gate that a `kubectl apply` bypasses does not constrain the path that an incident takes.
3. **The failure of the gate itself is survivable and understood.** Each layer here fails differently. A layer whose failure blocks all deploys has a price to match.
4. **No component is added only for enforcement**, per principle 2 of [ADR-0000](0000-platform-foundations.md). An in-tree mechanism wins over a controller that expresses the same rule.

## Considered options

| Option | Reaches state that CI did not create | Failure mode | Added components | Verdict |
| --- | --- | --- | --- | --- |
| **Layered by class of invariant, one layer each** | yes, for the classes that need it | per layer, stated per layer below | none. Other ADRs already decide every mechanism | **Chosen.** It is the only option that answers driver 2 and driver 3 separately for each rule, not once for all rules *(reasoned)* |
| Everything in CI | **no.** A manual apply, a break-glass action, or a compromised pipeline is unchecked | fails open: a check that did not run counts as passed | none | Sound for repository properties and unsound for cluster properties. That difference is the question to decide |
| Everything through one policy engine | yes | **one [webhook whose outage blocks every deploy](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#failure-policy)**, including the deploy that fixes it | none beyond Kyverno | It puts all of driver 3's risk into a single component, to buy uniformity that nobody reads. It would also move rules that the API server enforces in-tree onto a controller, against driver 4 |
| A choice in each ADR, unstated | not consistently | unknown until an incident | none | The honest baseline: what exists without this document. It produces both failure modes in the Context above. Neither is visible until someone tests a rule |

## Decision

**An invariant is enforced at the earliest layer that the constrained party cannot bypass.** Earliest, because feedback before merge is cheaper than feedback at deploy. Cannot bypass, because this makes it enforcement and not advice. The two conflict in exactly one case, and driver 2 wins that case.

| Class of invariant | Layer | Why this layer owns it |
| --- | --- | --- |
| Repository properties: layout, naming, drift in generated code, contract shape, and prose | **CI lints**, per [ADR-0101](0101-monorepo.md) and [ADR-0303](0303-api-contracts-and-lifecycle.md) | The subject is a file in a pull request. There is no cluster state to check and nothing to bypass. An unmerged branch cannot break a rule about `master` |
| Workload privilege: capabilities, host namespaces, root, and volume types | **Pod Security Admission**, per [ADR-0200](0200-cluster-topology.md) | It is in-tree, so driver 4 decides it. It uses namespace labels with a pinned `enforce-version`, and there is no component to run |
| Image provenance: signatures, attestations, and digest pins | **Kyverno**, per [ADR-0104](0104-supply-chain-security.md) | The property is about the artefact that a pod *runs*. Only the cluster can check it at the moment it runs the pod. CI proves that the image was signed. Admission proves that this pod uses a signed image |
| Reachability: which workload may open a connection to which | **CiliumNetworkPolicy**, per [ADR-0206](0206-cluster-networking.md) | It is enforced in the datapath, so it constrains a compromised pod, not only a cooperating one. Nothing above the network can express it |
| Resource governance: requests, limits, quota, and eviction order | **In-tree API objects**, per [ADR-0204](0204-resource-management.md) | The API server itself enforces `LimitRange`, `ResourceQuota`, `PriorityClass`, and `PodDisruptionBudget`. Kyverno could express the same rules. It would add a controller to the path and reach nothing new |
| Request authorization: who may call what | **The edge and the application**, per [ADR-0305](0305-edge-auth-and-traffic-policy.md) and [ADR-0304](0304-identity-and-authorization.md) | The subject is a request, not an object, so no admission layer sees it |

**A rule appears in one row.** Where two layers could hold a rule, the table above decides. The losing layer does not carry a weaker copy for feedback. That copy is the drift that this ADR prevents.

**One rule is enforced twice on purpose, and this exception shows the test.** CI lints digest pinning, and admission enforces it, per [ADR-0104](0104-supply-chain-security.md). The two checks have different subjects. The lint reads the values file that a human edits. Admission reads the pod spec that a chart rendered. Neither is a copy of the other, because a rendered pod spec can carry a floating tag that no values file contains.

### Each layer fails differently, and the difference is the price

| Layer | On failure | Blast radius |
| --- | --- | --- |
| CI lints | **open.** A check that did not run counts as passed | one merge, and everything that follows from it |
| Pod Security Admission | fails with the API server | nothing separate. If it is down, nothing is admitted anyway |
| Kyverno | **closed, cluster-wide.** A failing webhook blocks admission for everything it matches | every deploy, including the deploy that would fix it. This is the largest single-component blast radius on the floor, per [`operational-surface.md`](../operational-surface.md). The break-glass is the kubeconfig path from [ADR-0202](0202-secrets.md), plus removal of the webhook configuration |
| CiliumNetworkPolicy | **last known good.** Policy that is already programmed stays in the eBPF maps when the agent restarts | New pods get no policy until the agent is back. So avoid scheduling during an agent outage |

Kyverno's row is the reason driver 3 is a separate driver. It is the only layer here whose own outage is an incident. For the same reason, its scope stays at image provenance and does not grow to everything a policy engine can express.

### The annotation is the index

The Rules annotations from [ADR-0001](0001-documentation-and-output-conventions.md) name the layer:

- `(CI: <task>)` is a lint.
- `(enforced: <policy>)` is admission or the datapath.
- `(ref: <standard>)` is an adopted external standard.

Review enforces an unannotated rule. This is a stated position, not an omission. A rule may name a layer that the table above does not assign to its class. That mismatch is a defect in the rule or in the table.

## Consequences

### Positive

- A reviewer of a new rule answers one question: which class of invariant this is. The layer follows from the answer.
- The four mechanisms stop being four independent policies. They become one statement with four implementations.
- The blast-radius table shows the Kyverno concentration where it is decided. Nobody has to discover it during an outage.
- An argument against scope growth in the policy engine is on record. A refusal of the next rule that Kyverno could express costs a link, not a debate.

### Negative and Risks

- **Review enforces the layer assignment.** A rule can sit at the wrong layer, and nothing rejects it. The annotation makes the mistake visible in a diff, but it does not prevent it.
- **The rule of earliest and unbypassable has a real conflict in it**, and unbypassable wins every time. This delays feedback for the image-provenance class: a violation shows at deploy, not at merge.
- **CI lints fail open by design.** Nothing here changes that. The class assigned to them is the class where failing open is acceptable, because the subject never reaches the cluster.

## Rules

- Every invariant is enforced at exactly one layer, chosen by its class in the assignment table. A second copy at another layer is not added for feedback.
- CI enforces repository properties. Pod Security Admission enforces workload privilege. Kyverno enforces image provenance. CiliumNetworkPolicy enforces reachability. In-tree API objects enforce resource governance.
- Kyverno's scope is image provenance. An extension to a class that this ADR assigns elsewhere requires an amendment to this ADR. `(enforced: Kyverno)`
- A rule carries the annotation of the layer that enforces it. Review enforces an unannotated rule. `(ref: ADR-0001)`
- No component is added whose only purpose is to enforce a rule that an in-tree mechanism already enforces.
