# ADR-0207: Cluster Storage and Backups

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0200](0200-cluster-topology.md), [ADR-0205](0205-environment-parity.md), [ADR-0300](0300-data.md), [ADR-0302](0302-temporal.md), [ADR-0500](0500-observability.md)
- **Decides:** Volumes are node-local, object storage is SeaweedFS in every environment and outside the cluster in production, and backups go to it under Object Lock.

## Context

[ADR-0200](0200-cluster-topology.md) puts three Talos nodes per environment on plain instances. Two separate storage questions follow:

- What backs a pod's volume between reschedules.
- Where durable data lives.

They are separate because the answer to the second removes most of the first. Postgres backups, logs, traces, profiles, and the registry's own store all live in object storage. So a block volume holds only cache and working state, and replication of it would pay for durability twice.

The store that holds durable data is also **what a cluster is rebuilt from**. So it cannot share a failure domain with the cluster it restores. This constraint makes this ADR a decision and not only a component choice.

Parity comes from [ADR-0205](0205-environment-parity.md). Topology may differ between environments. Interfaces may not.

## Decision drivers

1. **The recovery path survives the loss of the cluster.** The store that holds the backups is outside the failure it recovers from.
2. **The recovery path survives a leaked credential.** With an operator credential that can delete backups, one incident can cause a total loss. So immutability is a requirement, not a feature.
3. **One implementation everywhere**, per [ADR-0205](0205-environment-parity.md). S3 dialects differ in the places that fail late. A difference that only production exercises is found in production.
4. **Operational sovereignty**, per principle 3 of [ADR-0000](0000-platform-foundations.md). The store is a component that the platform runs, not a signup.
5. **The always-on floor is the budget**, per principle 2. Durability is bought once, at the layer that needs it.

## Considered options

### Block storage

Object storage carries the durable data. So this section decides only the volumes that back a pod between reschedules.

| Option | Added components | Survives node loss | Talos cost | Verdict |
| --- | --- | --- | --- | --- |
| **`local-path-provisioner`** | one small provisioner | **no.** A volume is pinned to its node | none. It uses a directory under `/var`, the writable path | **Chosen.** The durable data is already off-cluster, so replication here would pay twice *(reasoned)* |
| Longhorn | a controller, engines on each node, and a UI | yes, replicated | the `iscsi-tools` and `util-linux-tools` extensions, a data path under `/var/mnt`, and a separate disk | The answer when a volume is too large to lose. It is the storage trigger below. It is an OS-image change, not a chart |
| OpenEBS Mayastor | a control plane, and data planes on each node | yes | hugepages and a dedicated device | Longhorn's guarantee with higher performance and a larger operational surface. No component here has a workload profile that needs it |
| Rook-Ceph | a full Ceph cluster | yes, strongly | extensions and dedicated disks | A distributed storage system to operate. Principle 2 refuses this for volumes that hold no durable data |
| A provider CSI driver | none in the cluster | yes | none | It fails driver 4, and it couples the cluster to the API of one provider again |

### Object storage

One component runs in every environment. The parity contract is **the same implementation**, not only the S3 API, per driver 3. The dialects differ in multipart, conditional writes, checksum trailers, and list pagination.

**In production, the store runs outside the cluster.** That is the only difference between environments, and it is driver 1. External means outside the cluster, not outside the organisation. Hardware that the organisation owns meets the requirement. A provider bucket is the concession in [`adoption-path.md`](../adoption-path.md), not the default.

So the selection is one comparison against one set of requirements. The store runs at `instances=1` on a laptop, per [ADR-0600](0600-local-development-loop.md). It also runs as a durable off-cluster store for Postgres backups with their WAL archive, Loki, Tempo, and Pyroscope.

This store holds backups that an operator credential can reach. So driver 2 makes **Object Lock a requirement, not a feature**. It is the only control that survives an attacker with valid credentials.

| Option | One component everywhere | Object Lock | Storage cost | Operator UI | Verdict |
| --- | --- | --- | --- | --- | --- |
| **SeaweedFS** | **yes.** `weed mini` is the whole store in one process for local and dev. Production runs master, volume, filer, and S3 off-cluster, from the same binary | **yes.** Versioning with GOVERNANCE and COMPLIANCE retention | erasure coding on warm data, about 1.4 times | master, filer, and admin UIs, started by the same command | **Chosen.** It is the only option that meets driver 3 and driver 2 together *(reasoned)* |
| Garage | yes. A single binary in both | **no, and it cannot get it.** Object Lock requires versioning, and Garage does not implement versioning | replication only, **3 times** | none first-party. A CLI and an HTTP admin API | The best fit and the lightest to operate. Without Object Lock, it is a **bet, not a deferral**. There is no seam, and a later adoption is an object-store migration that moves every byte |
| Ceph RGW | **no.** It cannot run in the local loop in any configuration | yes, the most complete | erasure coding, tunable | Ceph Dashboard, the strongest here | Driver 3 removes it. It stays the right answer for an organisation that **already operates Ceph**. There, the extra cost is a pool and a gateway, not a second distributed system |
| MinIO | yes | yes | erasure coding | removed from the community edition in 2025 | The incumbent, and **no longer maintained**. The repository was archived in April 2026. Distribution is source-only, and the maintained build is an AIStor binary under a proprietary licence. The risk is abandonment, not novelty. [ADR-0502](0502-alerting-and-on-call.md) records the same failure for Grafana OnCall |
| RustFS | yes | young | not assessed | a console | Principle 4 puts object storage in the conservative class, and this slot is the data plane |
| A provider bucket in every environment | **no.** It breaks the offline local loop and puts a credential in the environment of every developer | yes | not applicable | the provider's | It gives up axis B on the one Core data path where the platform never recorded that choice. It is correct as a ranked concession, not as the default |
| Two implementations, one per tier, the honest baseline | no | varies | varies | varies | It buys a lighter component for non-prod. The price is a dialect gap that only production can find |

**Both remaining candidates had S3-dialect defects, and the failure modes were different.** In January 2025, AWS SDKs started to send CRC32 checksum trailers by default. Garage rejected those requests. SeaweedFS wrote the trailer into the stored object bodies. Both defects are fixed. Silent corruption on the path that Postgres backups use is the more serious failure. So *Negative and Risks* records it as a current risk, not as history.

## Decision

| Kind | Day one | On the storage-scale trigger |
| --- | --- | --- |
| Block | `local-path-provisioner`, backed by a directory under `/var`. That is the writable path on a node that is otherwise read-only | Longhorn becomes the default for new volumes |
| Object | **SeaweedFS in every environment.** It runs in the cluster for local, dev, and staging, and **outside the cluster in production** | unchanged |

**Outside the cluster is a failure-domain requirement, not an implementation requirement.** In production, no store on the cluster it serves is acceptable, whatever the store is. This objection is separate from the component-weight objection that rejects Rook-Ceph for block storage above, and it is stronger.

**Placement depends on whether the data must outlive the cluster.** This store holds the backups that a rebuild reads, so its contents cannot be replaced. Nothing can regenerate the point-in-time history of a database. So the store goes off-cluster where recovery is real. The image registry is the opposite case, per [ADR-0105](0105-image-registry.md). CI can push its contents again, or they can be read again from a surviving bucket. So the registry needs no independent survival, and it stays in the cluster. The store and the registry differ because of this rule, not by accident: **off-cluster where the data cannot be regenerated, in the cluster otherwise.**

**Production buckets enable Object Lock.** The store sits inside the same administrative boundary as the cluster whose backups it holds. WORM retention stops a compromised or mistaken credential from destroying the recovery path as well.

**The lock window EQUALS the backup retention. It is not a minimum.** A longer lock is not safer. CNPG deletes backups after their retention ends. A lock that lasts longer than the retention makes each of those deletes fail. The bucket then grows without limit, and the operator logs delete errors that nobody reads. This is a slower outage than the one the lock prevents. Equality keeps the two in agreement.

**The mode is set per bucket, and it depends on what the bucket holds.**

| Bucket | Mode | Why |
| --- | --- | --- |
| CNPG backups | **COMPLIANCE** | The lock exists for this bucket. Nobody can shorten or bypass COMPLIANCE, including the root credential. That is the threat: an attacker with valid credentials, or an operator with a bad one |
| Loki, Tempo, Pyroscope | **GOVERNANCE** | Operational telemetry with short retention and no role in recovery. Here, deletion on request is worth more than immutability. GOVERNANCE keeps deletion available to an authorised identity |
| The registry's bucket | **GOVERNANCE** | Images can be rebuilt from source, and the bucket holds no unique state, per [ADR-0105](0105-image-registry.md) |

**COMPLIANCE conflicts with erasure, and this ADR discloses the conflict.** Nobody can delete a subject's data inside a locked backup before the window ends. That is the meaning of COMPLIANCE. So this ADR bounds the erasure obligation of [ADR-0301](0301-data-lifecycle-privacy.md):

- Erasure removes the subject from every live store immediately.
- Erasure removes the subject from backups **when the lock window expires**.

The bound is short, because the window equals the backup retention and is not longer. The platform states the bound to the subject, so nobody first finds it during an audit.

Loki, Tempo, CNPG backups, and Pyroscope write to the bucket. Prometheus keeps a local TSDB and needs no bucket. Its Mimir swap at Scale does need one, per [ADR-0500](0500-observability.md).

### The storage-scale trigger is a bet, not a seam

| Field | Value |
| --- | --- |
| **Trigger** | A Postgres restore rehearsal takes longer than half the RTO |
| **Seam** | ⚠ **none.** [Longhorn on Talos](https://longhorn.io/docs/latest/advanced-resources/os-distro-specific/talos-linux-support/) needs system extensions, a `/var/mnt` data path, and a separate disk. Its adoption rebuilds the installer image and reprovisions every node |
| **Cost if adopted late** | Every existing volume migrates per workload while the schematic changes under it. That is two migrations at once, not one |

The trigger is recovery time, not capacity. A local-path volume dies with its node. It comes back only through a restore from the archive, and the restore time grows with the data. The RTO in [ADR-0200](0200-cluster-topology.md) is 30 minutes. When a restore takes more than half of it, the loss of one node breaks the objective, and a replicated volume is the fix. The rehearsals in `docs/guide/disaster-recovery.md` record that time. Disk use is not a trigger. Longhorn keeps two or three replicas of every volume, so it needs more disk, not less. The capacity alerts cover a node that fills up.

### Backups, mandatory and off-cluster

| Data | Mechanism | Retention |
| --- | --- | --- |
| Postgres | CNPG `ScheduledBackup` to the external bucket, with WAL archiving for PITR | 30 days in prod, 7 days in non-prod |
| Temporal history | It lives on Postgres, so the row above covers it | the same as Postgres |
| Long-term observability data | already in the bucket. The cluster volume holds hot cache only | per lifecycle policy |
| Whole node | daily provider snapshots, as a fallback for catastrophic recovery | provider default |

A Temporal `Schedule` rehearses the restore quarterly and opens a tracking issue, per [ADR-0302](0302-temporal.md). [ADR-0200](0200-cluster-topology.md) sets the recovery objectives for these backups.

**The move to the Barman Cloud plugin is deferred.** CNPG's in-tree `barmanObjectStore` carries both backups and WAL archiving.

| Field | Value |
| --- | --- |
| **Trigger** | A CloudNativePG upgrade to 1.30, which removes the in-tree `barmanObjectStore` |
| **Seam** | ✓ One chart, `infra/helm/platform/postgres`, renders every backup and recovery setting. The bucket layout does not change |
| **Cost if adopted late** | None before the upgrade. At the upgrade, the chart moves in the same change, or archiving stops |

## Who provisions the production store

**The template does not provision it. This is a decision, not an omission.**

[ADR-0200](0200-cluster-topology.md) already makes Terraform a per-project tool and skips it where infrastructure is pre-provided. A reference module for the object store would reverse that for one component. A module must name a provider, and that choice picks a cloud for every adopter. It would do so for the one component that this ADR places outside the cluster and outside its failure domain. An adopter on a different provider would then delete a module instead of filling in a blank. That is worse than no module.

So the provisioning of the store is a **per-project obligation**. In exchange, the template owes a requirement exact enough to meet without guessing:

| Requirement | Why it is not negotiable |
| --- | --- |
| Outside the cluster's failure domain | A store on the cluster it backs cannot survive the loss it exists for |
| S3-compatible, addressed by endpoint and credentials | This is the whole interface that the platform uses. Anything that meets it works |
| Versioning enabled | Object Lock requires it. Without it, an overwrite is a deletion |
| Object Lock, COMPLIANCE on the backup bucket | The lock's threat model is a valid credential in the wrong hands |
| Lock window EQUAL to backup retention | A longer window makes CNPG's retention deletes fail, and the bucket grows without limit |
| Reachable from the cluster over TLS | The production store is not on the pod network |

An adopter who meets this table has met K2 on any provider, including a rack in an office. An adopter who cannot meet it sees exactly which line fails.

**The platform does not verify these requirements.** Nothing checks that the configured bucket has versioning and a lock window of the correct size. An adopter can point at a bucket with neither, and every backup appears to succeed until the restore that needs them. This check belongs in the platform, because the requirement is the platform's.

## Consequences

### Positive

- **One object store, one dialect, and one set of operator habits.** A multipart or checksum difference cannot hide until production, because every environment runs the same implementation.
- The recovery path survives the loss of the cluster and the loss of a credential. These are the two failures that a backup exists for.
- Block storage costs one small provisioner, because durability is bought once, at the object layer.

### Negative and Risks

- **Production object storage is a stateful component that the platform operates.** A provider would save this work. The platform gives up that saving so that the one Core data path is not a signup. The obligation falls on the same team that runs the cluster.
- **SeaweedFS's S3 layer is younger than its storage layer.** In January 2025, AWS SDKs started to send CRC32 checksum trailers. SeaweedFS wrote the trailer into stored object bodies and did not reject the request. This was silent corruption on the path that Postgres backups use, and it is fixed. Backup verification catches a recurrence, so the restore rehearsal is not optional.
- **One maintainer does most of the development.** Accepted under principle 4, on the same terms as the registry. The exit is a change of S3 endpoint plus a data copy, and the interface is the API, not the product.
- **The open version offers erasure coding at a fixed ratio.** Tuning it is a commercial upstream feature. This is enough here. The ADR records it so that nobody discovers it during a capacity exercise.
- **A block volume does not survive node loss.** This is correct for cache and working state. The trigger above says when it stops being correct.
- **Bucket fees grow with retention.** Lifecycle policies that move data to a cold tier after 30 days reduce the cost.

## Rules

- The storage class is `local-path-provisioner` over a directory under `/var` until the storage-scale trigger fires. After that it is Longhorn, with the extensions it requires.
- Object storage is SeaweedFS in every environment. No tier introduces a second S3 implementation.
- Production runs it outside the cluster. No object store that holds production data runs on the cluster it serves.
- Production buckets have Object Lock enabled, with the lock window EQUAL to the backup retention. A longer window makes CNPG's retention deletes fail, and the bucket grows without limit.
- The Object Lock mode is COMPLIANCE on the backup bucket and GOVERNANCE on the telemetry and registry buckets.
- Erasure reaches live stores immediately and locked backups when the lock window expires, and this bound is disclosed.
- Database backups are written off-cluster to that bucket, and the restore is rehearsed quarterly.
- Loki, Tempo, CNPG backups, and Pyroscope write to object storage, not to a block volume.
