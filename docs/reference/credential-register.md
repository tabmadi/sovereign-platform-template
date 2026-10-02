# Credential Register

This page records where each credential of this project is kept. It **never holds the value**. It holds only the credential's home and who can open it, per [ADR-0202](../adr/0202-secrets.md).

A newcomer reads this page and knows what to ask for and what to generate. If a credential is not on this page, nobody can find it during an incident. This register exists to prevent that failure.

**A generated project fills in the tables.** The project inherits the classes and the rule that sorts them. The rows belong to the project, and it adds each row when the credential comes into existence.

## The rule: sort by what a reader needs in hand

There are three homes. One test decides the home: **whether the credential is still needed when this repository and the cluster are both unreachable.**

| Class | Home | Read by holding |
| --- | --- | --- |
| **Machine-consumed**: a service, a cluster, or CI authenticates with it | SOPS-encrypted in this repository | a clone, an age key, and `sops` |
| **Break-glass**: a person uses it to reach or repair the infrastructure | SOPS here **and** an offline copy | the offline copy alone |
| **Root of trust**: it opens the two classes above | offline only, never committed | itself |

People get the middle row wrong most easily. A credential that repairs the machine that hosts the repository cannot live only in that repository. The outage that makes you need it is the outage that hides it, per [break-glass](../guide/break-glass.md).

The second row is empty for a project that provisions its infrastructure through a provider API, per [ADR-0200](../adr/0200-cluster-topology.md). The provider console login is then the break-glass credential, and the provider holds it. A project that operates its own hypervisor owns that row itself.

## Machine-consumed

| Credential | File | Recipients |
| --- | --- | --- |
| Per-environment platform secrets | `infra/gitops/platform/<env>/secrets/` | engineers, that cluster, ops-recovery |
| The first operator's login of [ADR-0304](../adr/0304-identity-and-authorization.md) | the `first-operator` entry of `infra/gitops/platform/<env>/secrets/` | engineers, that cluster, ops-recovery |
| Local-tier values | `infra/gitops/platform/local/secrets/` | the committed throwaway key |
| The image-signing key of [ADR-0104](../adr/0104-supply-chain-security.md) | `infra/auth/cosign/` | engineers, CI, ops-recovery |

The local tier is the one exemption in [ADR-0202](../adr/0202-secrets.md). Its private key is committed, because it opens only throwaway values.

## Break-glass

| Credential | Where | Why it is not only here |
| --- | --- | --- |
| Hosting provider console | offline | it reinstalls a host, including the one that holds the repository |
| Domain registrar | offline | it is the recovery path when DNS itself is the failure |
| Second-factor recovery codes | offline | they are needed when the factor is lost, and at that moment no tooling is available |

**Offline means a medium with no availability dependency**: paper in a drawer, or a key kept apart from the laptop. A hosted password manager serves the same purpose and is an equally correct choice. A self-hosted one on this project's own infrastructure is not correct, because it shares fate with what it must recover.

## Roots of trust

| Credential | Where | Never |
| --- | --- | --- |
| An engineer's age private key | that engineer's laptop, plus an offline backup | committed, shared, or held in any shared service |
| The ops-recovery age key | offline, split across two or three seniors | online, or whole on one machine |
| A cluster's age key | inside that cluster. On Talos, also in the SOPS-encrypted machine config. To replace a lost key, create a new key and run `mise run secrets:updatekeys` | backed up on its own, committed in the clear, or on a laptop |

**An age key is one line of text, and its loss costs every secret that it opens.** Back it up in the same way as the break-glass credentials. Treat the two as one habit, not two.

## Adding one

1. Decide its class with the test above.
2. Put a machine-consumed credential in the matching `*.enc.yaml`. Or create a new file with its own rule in `.sops.yaml`.
3. Run `mise run secrets:updatekeys` and commit the diff.
4. Add a row here in the same pull request. The row is the deliverable. The value never appears in a row.
