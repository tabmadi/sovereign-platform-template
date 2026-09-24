# Credential Register

Where every credential this project holds is kept — **never the value**, only its
home and who can open it ([ADR-0202](../adr/0202-secrets.md)).

A newcomer reads this page and knows what to ask for and what to generate. A
credential absent from it is one nobody can find during an incident, which is the
failure this register exists to prevent.

**A generated project fills the tables in.** The classes and the rule that sorts
them are inherited; the rows are the project's own, and are added as each
credential comes into existence.

## The rule: sort by what a reader needs in hand

Three homes, decided by one question — **if this repository and the cluster are
both unreachable, is this credential still needed?**

| Class | Home | Read by holding |
| --- | --- | --- |
| **Machine-consumed** — a service, a cluster, or CI authenticates with it | SOPS-encrypted in this repository | a clone, an age key, and `sops` |
| **Break-glass** — a person uses it to reach or repair the infrastructure | SOPS here **and** an offline copy | the offline copy alone |
| **Root of trust** — opens the two above | offline only, never committed | itself |

The middle row is the one that is easy to get wrong. A credential needed to repair
the machine that hosts the repository cannot live only in that repository: the
outage that makes you want it is the outage that hides it
([break-glass](../guide/break-glass.md)).

The second row is empty for a project whose infrastructure is provisioned through
a provider API ([ADR-0200](../adr/0200-cluster-topology.md)): the provider console
login is the break-glass credential, and it is the provider's to hold. A project
that operates its own hypervisor owns that row itself.

## Machine-consumed

| Credential | File | Recipients |
| --- | --- | --- |
| Per-environment platform secrets | `infra/gitops/platform/<env>/secrets/` | engineers, that cluster, ops-recovery |
| Local-tier values | `infra/gitops/platform/local/secrets/` | the committed throwaway key |
| The image-signing key ([ADR-0104](../adr/0104-supply-chain-security.md)) | `infra/auth/cosign/` | engineers, CI, ops-recovery |

The local tier is the one exemption in [ADR-0202](../adr/0202-secrets.md): its
private key is committed, because it opens throwaway values only.

## Break-glass

| Credential | Where | Why it is not only here |
| --- | --- | --- |
| Hosting provider console | offline | it is how a host is reinstalled, including the one holding the repository |
| Domain registrar | offline | it is the recovery path when DNS itself is the failure |
| Second-factor recovery codes | offline | they are needed when the factor is lost, which is not a moment with tooling |

**Offline means a medium with no availability dependency**: paper in a drawer, or a
key kept apart from the laptop. A hosted password manager serves the same purpose
and is an equally correct choice; a self-hosted one on this project's own
infrastructure is not, because it shares fate with what it is meant to recover.

## Roots of trust

| Credential | Where | Never |
| --- | --- | --- |
| An engineer's age private key | that engineer's laptop, plus an offline backup | committed, shared, or held in any shared service |
| The ops-recovery age key | offline, split across two or three seniors | online, or whole on one machine |

**An age key is one line of text, and losing it costs every secret it opens.** Back
it up the same way the break-glass credentials are backed up, and treat the two as
one habit rather than two.

## Adding one

1. Decide its class with the question above.
2. Machine-consumed goes in the matching `*.enc.yaml`, or a new one with its own
   rule in `.sops.yaml`. Run `mise run secrets:updatekeys` and commit the diff.
3. Add a row here in the same pull request. The row is the deliverable; the value
   never appears in one.
