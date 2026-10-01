# ADR-0202: Secrets Management

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0003](0003-naming-and-identifiers.md), [ADR-0101](0101-monorepo.md), [ADR-0200](0200-cluster-topology.md), [ADR-0201](0201-gitops.md), [ADR-0205](0205-environment-parity.md)
- **Decides:** Secrets are SOPS-encrypted to three classes of age recipient, and an operator decrypts them in the cluster.

## Context

Every environment needs secrets: database passwords, JWT signing keys, OAuth client secrets, and API tokens. All of them require five properties:

- **Versioned** with the rest of the configuration, so git can reproduce a deploy.
- **Never plaintext** to anyone outside the recipient list.
- **Decryptable in the cluster** by the GitOps controller at sync time, with no human in the loop.
- **Decryptable locally** by engineers who run against real infrastructure.
- **Rotatable** by a known procedure, after a compromise and at offboarding.

## Decision drivers

1. **Self-hosted and open source.** No managed service sits in the secret path, per principle 3 of [ADR-0000](0000-platform-foundations.md).
2. **GitOps-native.** Secrets reach the cluster in the same way as everything else: a git commit that Argo CD reconciles.
3. **One mechanism for every environment**, local included, per [ADR-0205](0205-environment-parity.md).
4. **No extra stateful component** where the platform can avoid one, per principle 2 of [ADR-0000](0000-platform-foundations.md).

## Considered options

| Option | Added stateful component | An engineer can decrypt locally | Diff granularity | Verdict |
| --- | --- | --- | --- | --- |
| **SOPS with age** | none. The operator is stateless | **yes**, with the engineer's own key | per value. The structure stays readable, and values are encrypted blobs | **Chosen.** It is the only option that meets drivers 3 and 4 together *(reasoned)* |
| SOPS with GPG | none | yes | per value | It needs a key server, a web-of-trust ceremony, and a multi-line key format. age has a single-line public key and no ceremony |
| SOPS with a cloud KMS key | none | through the provider, with provider credentials | per value | The chosen file format, with its root of trust outside infrastructure that the platform controls. Driver 1 rejects it, for the same reason as the provider row below. age needs no service |
| sealed-secrets | a controller that holds a key. The controller generates, backs up, and rotates the key | **no. The encryption is one-way by design** | per value. `encryptedData` is a map per key. The ciphertext is non-deterministic, so re-sealing also rewrites values that did not change | It fails driver 3. An engineer cannot read a committed secret or run against one, so local and cluster need different mechanisms |
| Vault or OpenBao | **a service to run, unseal, back up, and upgrade** | through the service | not applicable | It fails driver 4. Its real value is dynamic short-lived credentials. That is a separate question from the storage of static config |
| External Secrets Operator | a controller **plus a store behind it** | through that store | not applicable | It can meet driver 1, because OpenBao and Infisical self-host. It fails driver 4 worse than the row above: the same stateful store, plus a sync controller |
| A provider secret manager, synced in | only a controller in the cluster | through the provider | not applicable | It fails driver 1 completely. The secret path leaves infrastructure that the platform controls, and the provider becomes a bootstrap dependency |
| Uncommitted `kubectl create secret`, the honest baseline | none | not applicable. Nothing is committed | not applicable. The values are not in git | The repo can no longer reproduce an environment. Each value exists only in the shell history of the person who created it |

### Detecting a plaintext secret

Correct storage of secrets and detection of a secret stored wrongly are different questions. The second needs its own answer, because a rule that only review enforces has no gate.

| Option | Runtime | What it costs to run in CI | Verdict |
| --- | --- | --- | --- |
| **gitleaks** | a single Go binary | nothing beyond the binary. It reads the tree and the history offline | **Chosen.** It is the only option here that adds no runtime and makes no network call. So it can run in a pre-commit hook as well as in CI *(documented)* |
| trufflehog | a single Go binary | outbound calls to the providers of the credentials it finds | Its main feature is **verification**: it asks the provider whether a found credential is live. That has real value on a large estate. It also puts CI on the network path to every third party that a false positive names |
| detect-secrets | Python | a Python toolchain in every clone and every runner | It fails principle 6 of [ADR-0000](0000-platform-foundations.md). With its baseline-file workflow, a reviewer cannot tell an unreviewed finding from a reviewed one |
| Review alone, the honest baseline | none | none | This repository held this position. It is the one defect class that survives its own fix. A revert of the file leaves the value in history, so the remedy is rotation |

**A history scan has a separate scope from a tree scan**, because the two answer different questions. The working-tree scan checks that the next change is clean. A pre-commit hook needs this. The history scan checks for an old committed secret that was never rotated. This is a CI question, and CI answers it once per branch, not once per commit.

## Decision

### SOPS with age recipients

[`sops`](https://github.com/getsops/sops) encrypts at the key level. Values appear in diffs as encrypted blobs, and the structure stays reviewable. [`age`](https://github.com/FiloSottile/age) supplies the recipients.

### Three recipient classes

Every encrypted file has exactly three recipient classes, declared in `.sops.yaml` at the repo root.

| Class | Naming | Where the private key lives | Purpose |
| --- | --- | --- | --- |
| **Per-engineer** | the engineer's `{handle}`, per [ADR-0003](0003-naming-and-identifiers.md). For example, `eng_alice`. Every key traces to a person | `~/.config/sops/age/keys.txt` on that laptop. It never leaves the laptop | Daily access. Scoped by project and handle, not by environment |
| **Per-cluster** | `{project}-{env}` | Only in that cluster, as a Secret in the `sops` namespace, created at bootstrap. The local tier's key is the exception: it is committed | Decryption in the cluster |
| **Ops-recovery** | one key | offline, on the hardware tokens of more than one senior engineer | Recovery of a lost cluster key without re-encryption of every secret. Disaster recovery only |

`.sops.yaml` declares creation rules per path:

- Files under `infra/gitops/platform/<env>/secrets/` are encrypted to the cluster key of that environment, the engineers, and ops-recovery.
- Files outside an environment path are encrypted to the engineers and ops-recovery only.

**The local tier is the exemption, and the same file bounds it.** A local cluster lives only as long as a `mise` task, and no bootstrap step creates a key for it. So the local private key is committed at `infra/gitops/platform/local/age.key`, and its creation rule names that key as the only recipient. The key is safe because of what it opens, not because it is secret. It opens throwaway values in a cluster that holds no real data, per [ADR-0205](0205-environment-parity.md). A real credential encrypted to this key is a leak, not a shortcut. The preview tier uses the same path for the same reason.

**The committed key is per project, not per template.** A template that ships one local key ships a default credential to every project generated from it. The reasoning that the key is throwaway does not travel with the copy. So `cluster:up` creates a new local key on first use and re-encrypts the local bundle to it, through `mise run bootstrap`. The shared key then stops opening a project as soon as anyone runs its cluster. This is not a second exemption. It keeps the first one bounded to one repository.

The `secrets` ApplicationSet delivers these per-environment files to the cluster at sync-wave 1, per [ADR-0201](0201-gitops.md). This wave comes after the operator in the base tier and before the data tier that consumes the Secrets.

### In-cluster decryption

[**sops-secrets-operator**](https://github.com/isindir/sops-secrets-operator) watches `SopsSecret` custom resources that hold SOPS-encrypted values. It produces native Kubernetes `Secret` objects. The flow has three steps:

1. Argo CD reconciles the encrypted file with the rest of the manifests.
2. The operator decrypts it and creates the `Secret`.
3. The pod consumes the Secret through standard `envFrom` or `volumeMounts`.

Service authors reference secrets by Kubernetes Secret name in Helm values, in the same way as any other Secret. The service cannot see the encryption layer.

| Option | Where the age key lives | What decrypts | Verdict |
| --- | --- | --- | --- |
| **sops-secrets-operator** | one Secret, read by the operator | a controller, once per `SopsSecret` | **Chosen.** The pod consumes a native `Secret` and never learns that SOPS exists |
| An init container per pod | mounted into every pod that reads a secret | the workload itself, before it starts | It spreads the key across every namespace and puts a decryption step in every service chart |
| Decryption in CI | the pipeline | the pipeline, which writes plaintext into the cluster | The repository can no longer reconcile the cluster, per [ADR-0201](0201-gitops.md). Argo CD would sync manifests whose values came from somewhere else |
| External Secrets Operator | in the external store | a controller, against that store | A controller plus a store behind it. *Considered options* above rejects it |
| KSOPS or helm-secrets in Argo CD's repo-server | in Argo CD's namespace | Argo CD, at render time | It has one component fewer, and a worse place for the plaintext. Argo CD caches manifests rendered by plugins, with their secrets, in its Redis. It serves them through the repo-server API, so every reader of either one reads every secret. The repo-server also carries a plugin that each Argo CD upgrade must keep working |

### Local decryption

Run `mise run secrets:age` once. After that, `cluster:up` and any `sops decrypt` work with no more configuration. To run against the secrets of a real environment:

```sh
sops exec-env infra/gitops/platform/dev/secrets/platform.enc.yaml -- mise run -C services/<svc> server
```

The inner loop needs no decryption. Each service's `.env.example` carries local development credentials. It is copied to `.env` and loaded by the service's `.mise.toml`, so `mise run server` works alone.

### Key lifecycle

| Event | Procedure |
| --- | --- |
| Onboarding | The engineer runs `mise run secrets:age`, opens a PR that adds the public key to `.sops.yaml`, and runs `mise run secrets:updatekeys`. The PR diff is the audit trail |
| Offboarding | Remove the public key, run `mise run secrets:updatekeys`, and **rotate every secret that the engineer could read**. Removal of a recipient re-keys later versions only. Every published commit stays readable by the key it was encrypted to. Rotation is standing policy, whatever the reason for the departure |
| Cluster-key rotation | Generate a new pair. Add the public key as an extra recipient on environment-scoped files. Update the Secret in the cluster. Remove the old key after one full sync cycle |
| Ops-recovery rotation | A new key is generated each year as part of the security review. The old key is destroyed |

### Backups

The encrypted files live in git, so they have git's distribution. The private keys do not.

| Key | Backup |
| --- | --- |
| Engineer | none. The key is personal. After a loss, the engineer runs the onboarding flow again with a new key |
| Cluster | backed up, encrypted to ops-recovery, in the same off-cluster bucket that [ADR-0207](0207-cluster-storage.md) uses |
| Ops-recovery | offline copies on the hardware tokens of more than one senior engineer, so a single departure does not lose recovery |

## Consequences

### Positive

- Secrets are versioned in git like everything else. There is no separate state store to operate, back up, or upgrade.
- Local and production parity is exact: an engineer and the cluster decrypt the same encrypted file.
- Onboarding is a PR. Offboarding is a PR plus a rotation runbook.
- Three recipient classes are few enough to remember, and they map directly onto an access review.

### Negative and Risks

- **Offboarding requires re-encryption of every file and rotation of every secret.** The number of secrets one engineer could read sets the work, and that is every secret in the repo. The [secrets runbook](../guide/secrets-runbook.md) holds the steps.
- **A lost engineer key loses that engineer's access.** Accepted: generate a new key, open a PR with the new public key, and onboard again.
- **A compromised cluster key exposes that environment's secrets to anyone with later git access.** The rotation procedure reduces the risk. So does the limit of cluster keys to environment-scoped files.
- **The ops-recovery key is a high-value target.** Offline storage on hardware tokens and yearly rotation reduce the risk.
- **Credentials are static.** Rotation is a procedure, not an expiry. The rejected options offer one thing: dynamic short-lived credentials. Their adoption is a separate decision with its own operational cost.

## Rules

- Plaintext secret values do not appear in any committed file. The one exemption is the local tier's age private key at `infra/gitops/platform/local/age.key`. It decrypts throwaway local values only, per [ADR-0205](0205-environment-parity.md). `(CI: lint:secrets)`
- All committed secrets are SOPS-encrypted to age recipients listed in `.sops.yaml`.
- Every encrypted file outside the local tier has exactly three recipient classes: per-engineer keys, the cluster key of the matching environment, and the ops-recovery key. Local files are encrypted to the committed local key alone.
- Age private keys are not stored in shared services. Engineer keys live on laptops. Cluster keys live only in the cluster they belong to, except for the local tier's exemption.
- A credential that no machine consumes is registered in [`docs/reference/credential-register.md`](../reference/credential-register.md) with its home, never its value.
- A credential that reaches or repairs the infrastructure that serves this repository is also held offline. A recovery credential stored only inside what it recovers is unreachable at the moment it is needed.
- Every engineer and ops-recovery age private key has an offline backup. The key is one line of text, and it opens every secret encrypted to it. Without a backup, the loss of its laptop is a total loss.
- A cluster key is replaced, never restored. The replacement is a new key, its public half in `.sops.yaml`, and `mise run secrets:updatekeys`. Every file it opens is also encrypted to the engineers. So a lost cluster key costs one commit, and a backup of it is one more copy to guard.
- Service Helm values reference secrets by Kubernetes Secret name. Services do not call SOPS or age at runtime.
- Onboarding adds a public key by PR plus `mise run secrets:updatekeys`. Offboarding removes it by PR plus `mise run secrets:updatekeys`, plus rotation of every secret that the engineer could read.
- Rotation at offboarding is mandatory, whatever the reason for the departure.
- The ops-recovery private key is never online and never on a single machine, and it is rotated every year.
- The sops-operator produces every cluster Secret from an encrypted file in the repo. `kubectl create secret` is not used.
- A change to a Secret's data rolls every Deployment, StatefulSet, and Temporal WorkerDeployment that references it, so a rotation reaches the process that reads it. No restart is left to a runbook. `(enforced: Kyverno)`
