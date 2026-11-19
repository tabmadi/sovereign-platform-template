# ADR-0200: Cluster Topology and Hosting

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0113](0113-supply-chain-security.md), [ADR-0201](0201-gitops.md), [ADR-0203](0203-policy-enforcement.md), [ADR-0205](0205-environment-parity.md), [ADR-0206](0206-cluster-networking.md), [ADR-0207](0207-cluster-storage.md)
- **Decides:** Production runs upstream Kubernetes on Talos, with three nodes per environment on plain compute instances that the project provisions or receives.

## Context

There are three environments: dev, staging, and prod. Each is one cluster. Workloads include stateless application services, stateful platform components, and ingress.

This ADR answers five questions:

- Where production runs.
- What a node is.
- What shape a cluster has on day one.
- How a cluster grows.
- What recovery costs.

Two other questions are settled at the same bootstrap, but each has its own decision. Each is load-bearing for readers who never touch provisioning. [ADR-0206](0206-cluster-networking.md) decides the pod network. [ADR-0207](0207-cluster-storage.md) decides volumes and backups. [ADR-0205](0205-environment-parity.md) decides what may differ between environments. [ADR-0600](0600-local-development-loop.md) decides the laptop.

## Decision drivers

1. **Operational sovereignty**, per principle 3 of [ADR-0000](0000-platform-foundations.md). Nobody outside the organisation can change the terms on which the control plane runs. Fees per cluster, per load balancer, and per volume do not add up across a growing fleet.
2. **A node matches its description.** A host can drift from what it is declared to be. This gap is a failure class of its own, and this layer can remove it instead of monitoring it.
3. **Boring by default, novel where it removes a class of failure**, per *spend novelty by exit cost* in [ADR-0000](0000-platform-foundations.md). The platform adopts a less widely operated component only where it removes a category of failure. Improving on a category is not enough, and the ADR names the category.
4. **Losing one node is not downtime.**

Parity at the manifest layer is a constraint from [ADR-0205](0205-environment-parity.md), not a driver here. Topology may differ between environments. Charts and commands may not.

## Considered options

### The orchestrator itself

Kubernetes is Tier 1, per [ADR-0002](0002-tool-adoption.md). Every chart, policy, and operator, and the whole GitOps layer, use its API. A platform that assumes Kubernetes without a comparison cannot justify its weight.

| Option | 1 Sovereignty | 3 Novelty spent where it removes a failure class | 4 One node lost is not downtime | Stateful operators, the axis C obligation | Verdict |
| --- | --- | --- | --- | --- | --- |
| **Upstream Kubernetes** | **Yes. Self-hosted, with no fee per cluster** | **The most widely operated orchestrator** | **Yes, with three control-plane nodes** | **Yes. CNPG, Cilium, cert-manager, Argo CD, and Kyverno exist because of it** | **Chosen. It is the largest term in [`operational-surface.md`](../operational-surface.md), and the operators pay for it** |
| Nomad | Under the BUSL since 1.7, so one vendor sets the terms | Widely operated, and much lighter: one binary and no CRD layer | Yes | No. It has no CNPG equivalent, so Postgres HA, backup, and PITR become first-party work | Rejected on driver 1 and on the operators. It is the runner-up on weight |
| Docker Swarm | Yes | Maintained by Mirantis, with no policy or admission layer | Yes | No | Rejected on the operators |
| systemd units on plain instances | Yes | Yes | No. Each service needs its own failover | No | Rejected on driver 4 at axis A high |
| A self-hosted PaaS: Dokku, CapRover, or Coolify | Yes | Each has its own fixed deploy path | Coolify and CapRover cluster partly | No operator model for stateful workloads | Rejected on the operators |
| Managed Kubernetes | No. The provider sets the terms of the control plane | Yes | Yes | Yes | Rejected on driver 1 |

Sources:

- Nomad and the other HashiCorp products moved to the BUSL in August 2023: [HashiCorp, licensing FAQ](https://www.hashicorp.com/license-faq).
- CloudNativePG runs only on Kubernetes: [CloudNativePG](https://cloudnative-pg.io/).
- Swarm mode and its maintainer: [Mirantis, Swarm](https://www.mirantis.com/software/swarm/).
- Kubernetes control-plane quorum: [Kubernetes docs, options for highly available topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/).

**Stateful workloads decide the comparison.** At axis C high, failover, backup, and point-in-time recovery are the core obligation of the platform. CloudNativePG expresses that obligation as four CRDs instead of a runbook and a cron job. Nomad's advantage in weight is real. The platform would spend it to buy back the same capability in first-party code.

### Node operating system

| Option | 1 Sovereignty | 2 A node matches its description | 3 Novelty spent where it removes a failure class | Verdict |
| --- | --- | --- | --- | --- |
| **Talos Linux** | **Yes. MPL-2.0, and bare metal is a first-class target** | **Yes. No shell and no SSH. An API applies one machine config document** | **It removes host drift as a class, which driver 3 asks for** | **Chosen** |
| Flatcar Container Linux | Yes | No. A shell and SSH stay, and only `/usr` is read-only | Widely operated | Rejected on driver 2 |
| Fedora CoreOS | Yes | No. A shell stays, and rpm-ostree layers change the host | Widely operated | Rejected on driver 2 |
| Bottlerocket | Partly. Its variants centre on AWS, with fewer for bare metal | Mostly. API-driven, with an admin container for a shell | Less widely operated than Talos off AWS | Rejected on driver 1 |
| NixOS, with Kubernetes from nixpkgs | Yes | Yes, as far as the Nix config declares the host. A shell stays | Kubernetes on NixOS is less widely operated than on Talos | Rejected on driver 3. NixOS stays the choice for the hosts outside the cluster, per [ADR-0100](0100-toolchain.md) |
| Debian stable, converged by Ansible | Yes | Only as far as the playbooks are complete | The most widely operated | Rejected on driver 2 |

Sources:

- Talos has no shell or SSH, and an API applies the machine config: [Talos docs, philosophy](https://docs.siderolabs.com/talos/v1.14/learn-more/philosophy).
- Flatcar mounts `/usr` read-only and keeps the rest: [Flatcar docs](https://www.flatcar.org/docs/latest/).
- Fedora CoreOS and rpm-ostree: [Fedora CoreOS docs](https://docs.fedoraproject.org/en-US/fedora-coreos/).
- Bottlerocket variants: [Bottlerocket, variants](https://github.com/bottlerocket-os/bottlerocket/blob/develop/variants/README.md).
- Kubernetes on NixOS: [NixOS wiki, Kubernetes](https://wiki.nixos.org/wiki/Kubernetes).

**The node is the only mutable part left in the system.** Git reconciles cluster state, per [ADR-0201](0201-gitops.md). Pods run on a base with no shell and no package manager, per [ADR-0111](0111-monorepo.md). The pod network is default-deny. Against that posture, the host shell is the one remaining escalation path and the one remaining source of drift. An immutable node makes the description and the described thing one object. This is the failure class that driver 3 requires the ADR to name.

### Kubernetes distribution

| Option | 1 Sovereignty | 2 A node matches its description | 3 Novelty | Verdict |
| --- | --- | --- | --- | --- |
| **Upstream Kubernetes, shipped by Talos** | **Yes** | **Yes. One artefact, one upgrade path, no installer** | **Upstream and conformant** | **Chosen** |
| k3s | Yes | Its installer and bundles live beside the OS. A chart here already replaces Traefik, ServiceLB, `local-path`, and CoreDNS | Conformant. Three-node HA needs etcd, so its small SQLite setup is not available | Rejected on driver 2 |
| k0s | Yes | A separate installer | Conformant | Rejected on driver 2 |
| kubeadm | Yes | A separate installer to operate | Upstream | Rejected on driver 2 |
| Managed Kubernetes: EKS, GKE, or AKS | No | Not applicable | Upstream | Rejected on driver 1 |

Sources:

- Talos ships upstream Kubernetes and upgrades it with the OS: [Talos docs, upgrading Kubernetes](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/upgrading-kubernetes).
- k3s bundles and its datastore options: [k3s docs, architecture](https://docs.k3s.io/architecture), [k3s docs, datastore](https://docs.k3s.io/datastore).

### Day-one node count

| Option | 4 One node lost is not downtime | Migration to HA later | Verdict |
| --- | --- | --- | --- |
| **Three nodes, embedded etcd** | **Yes** | **not needed** | **Chosen** |
| One node | No | a rebuild, with a data migration | Rejected on driver 4 |
| Two nodes | No. Two members have no quorum when one fails, so it is worse than one | a rebuild | Rejected on driver 4 |
| Three nodes, etcd on dedicated hosts | Yes | not needed | Rejected for day one. It becomes right when etcd competes with workloads |

Sources:

- etcd needs a majority of members: [etcd docs, failure tolerance](https://etcd.io/docs/v3.5/faq/#what-is-failure-tolerance).

### Provisioning

| Option | 1 Sovereignty | 2 A node matches its description | 3 Novelty | Verdict |
| --- | --- | --- | --- | --- |
| Terraform | No. The BUSL lets one vendor change the terms | Yes. A plan shows the change before it applies | The most widely operated | Rejected on driver 1 |
| **OpenTofu** | **Yes. MPL-2.0, under the Linux Foundation** | **Yes. The same plan and state model** | **A fork of Terraform with the same language and providers, the `siderolabs/talos` provider included** | **Chosen** |
| Pulumi | Yes, with a self-managed backend | Yes | A general-purpose language and a backend to run | Rejected. It adds a backend to the floor |
| Crossplane | Yes | Yes, reconciled | The cluster provisions its own base, a bootstrap cycle | Rejected. The creator runs inside the thing it creates |
| Provider CLIs in a script | Yes | No. No plan step | Yes | Rejected on driver 2 |

Sources:

- The licence of Terraform: [HashiCorp, licensing FAQ](https://www.hashicorp.com/license-faq).
- OpenTofu, its licence, and its home at the Linux Foundation: [OpenTofu](https://opentofu.org/), [OpenTofu FAQ](https://opentofu.org/faq/).
- The Talos provider in the OpenTofu registry: [siderolabs/talos](https://search.opentofu.org/provider/siderolabs/talos/latest).
- Crossplane provisions from inside a cluster: [Crossplane docs](https://docs.crossplane.io/).

## Decision

### Hosting

Production runs on **plain compute instances**, never on a provider's managed Kubernetes. Each project decides how the instances come to exist. Three modes are supported, and all three use the same bootstrap after provisioning.

| Mode | Provisioning | Bucket |
| --- | --- | --- |
| The project provisions its own infrastructure | OpenTofu under `infra/opentofu/` creates instances, network, LB, DNS, firewall, and bucket. It isolates the provider behind a stable interface. A provider change is a module swap, not a topology change | created |
| Infrastructure is pre-provided | OpenTofu is skipped. The machine configs are applied to existing Talos nodes named in a committed inventory | referenced by configuration |
| The project operates the hypervisor | Committed scripts create the nodes on hardware that the project runs. To rebuild a node, the project re-images its disk from the Talos image. OpenTofu is skipped: no provider API sits between the project and the metal, so the node lifecycle is a script against one hypervisor | created |

**The modes differ only in provisioning.** Everything after it is identical: machine configuration, Kubernetes, Cilium, and Argo CD. OpenTofu belongs to the project that owns its infrastructure. The second mode never calls it.

**In the third mode, the project owns provisioning, and no provider exists to address.** A hypervisor on the project's own hardware has no API that needs a plan in front of it. The lifecycle is create, re-image, and destroy against one machine. An idempotent script states it as completely as a module does. The mode keeps the requirement that OpenTofu enforces elsewhere: the node definitions, the image reference, and the creation steps are committed. A lost host then costs the time to re-run them, and never the knowledge of what they were.

**Pre-provided means pre-provided Talos.** Talos installs by booting its own image. It is not converged onto a running general-purpose distribution. So this mode requires nodes that already run Talos and are reachable on its API. A pre-provided fleet that runs anything else needs a reprovision, not a configuration step.

Self-hosting has an operational cost. The machine configuration under `infra/talos/` holds that operational knowledge as code. It is one document per node role, not a procedure that converges a host.

### Node OS

**Every node runs Talos Linux.** It has no SSH, no shell, no package manager, and no writable root filesystem. Configuration is a machine config document, applied over the node's gRPC API. `talosctl` is the only other interface.

| Concern | Mechanism |
| --- | --- |
| Configuration | one committed machine config document per node role, applied by the [`siderolabs/talos`](https://search.opentofu.org/provider/siderolabs/talos/latest) OpenTofu provider |
| OS upgrade | `talosctl upgrade`. It swaps between two image slots with rollback, one node at a time |
| Kubernetes upgrade | `talosctl upgrade-k8s`, versioned separately from the OS |
| Anything outside the base image, such as drivers, iSCSI, or GPU support | a system extension built into a custom installer image through [Image Factory](https://docs.siderolabs.com/talos/latest/learn-more/image-factory). It is referenced by schematic and pinned like any other artefact, per [ADR-0113](0113-supply-chain-security.md) |
| Machine secrets | the cluster CA and `talosconfig`, SOPS-encrypted in git like every other secret, per [ADR-0202](0202-secrets.md) |

Nothing runs on these nodes outside Kubernetes. The design makes a host agent, a debugging shell, and a one-off manual fix unavailable. This is the property the platform pays for, not a limitation it accepts.

This is narrower than it looks against [12-Factor XII](https://12factor.net/admin-processes). One-off admin work still runs, in the same image and release as the service:

- Migrations run as an init container, per [ADR-0300](0300-data.md).
- Operator tasks run through the admin UIs, per [ADR-0401](0401-internal-admin.md).

The host shell is unavailable. The one-off process is not.

### Topology and growth

On day one, each environment has three compute nodes that run Talos, with etcd on all three. All workloads run on this set. The nodes have many cores and large NVMe disks.

Each growth step is a deferral, and it has all three fields. A third trigger covers storage scale. [ADR-0207](0207-cluster-storage.md) owns it, because its seam is an OS-image change, not a node count.

| Trigger | Response | Seam | Cost if adopted late |
| --- | --- | --- | --- |
| CPU or memory stays above 70% for 7 days across the node set | Add worker agents. The control plane stays at three | ✓ A worker's machine config is a committed document, and joining is an apply. No workload is pinned to a node | Capacity arrives under pressure, not before it. The window becomes an incident, not a change |
| Regulated data with an isolation requirement | A dedicated cluster for that workload | ✓ Every environment is already one cluster, built from the same committed configuration. Another cluster is a values selection, per [ADR-0205](0205-environment-parity.md) | The regulated data has already shared a cluster with other data. No later separation undoes this |

### Workload hardening

Talos removes the host attack surface. Cilium removes the network attack surface. Neither limits what a *pod* may ask the kernel for. That is the third invariant.

**Every namespace enforces the `restricted` profile of the [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/).** The in-tree Pod Security Admission controller enforces it through namespace labels, with no extra component:

```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/enforce-version: <cluster minor>
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/audit: restricted
```

The version is pinned, not left at `latest`. A Kubernetes upgrade can add a criterion. With a pinned version, that criterion arrives as a deliberate bump in a reviewed PR. Without it, a batch of pods stops scheduling during a control-plane upgrade.

| Concern | Decision |
| --- | --- |
| Enforcement mechanism | **Pod Security Admission**, in the API server. Kyverno already runs, per [ADR-0113](0113-supply-chain-security.md), and it could express the same rules. But Kyverno gates *image provenance*. Workload privilege is a separate concern, and PSA enforces it with no extra component, per principles 2 and 5 |
| Service containers | The shared chart sets `runAsNonRoot`, a non-zero `runAsUser`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`, and `readOnlyRootFilesystem: true`. A service that needs a writable path declares an `emptyDir`, never a writable root |
| Components that need more | They run in **their own namespace**, labelled `privileged` or `baseline`. The namespace manifest records the reason. Cilium is the day-one case |
| Exception granularity | The namespace, because that is PSA's unit. A component that needs privilege never shares a namespace with one that does not |

### Provisioning order

```text
0. tofu apply   # instances, network, LB, DNS, firewall, bucket
                     # only when the project provisions its own infra
1. tofu apply   # applies the machine configs and bootstraps the cluster
                     # through the siderolabs/talos provider. Cilium comes
                     # with it as an inline manifest
2. just argocd-bootstrap <env>
                     # Argo CD, Traefik, and the cluster's age Secret. An
                     # Argo CD Application cannot install these three: one IS
                     # Argo CD, one owns the CRDs that the edge's routes name,
                     # and one decrypts every SopsSecret. Then the forge
                     # credential of a private repository, and the root
                     # Application. Argo CD reconciles the rest
```

In the other two modes, step 0 is the hypervisor's node-creation script, or nothing. Step 1 is `talosctl apply-config` per node, then one `talosctl bootstrap`.

**Step 2 is the bootstrap floor, and it is not optional.** Each of the three is a prerequisite of the thing that would otherwise deploy it:

- Argo CD cannot apply its own first install.
- The gateway's `Middleware` resources do not resolve until Traefik's CRDs exist.
- The sops-operator mounts the age key, and it cannot decrypt that key for itself.

Cilium joins them wherever it is not an inline manifest, per [ADR-0206](0206-cluster-networking.md).

No configuration-management step sits between provisioning and Argo CD, because no mutable host state exists to converge.

Git and the SOPS-encrypted machine secrets reproduce the cluster identity. Where a provider is addressed, one OpenTofu state file is also part of it. Where none is, the committed inventory, the node-creation scripts, and the referenced bucket are part of it.

### Disaster recovery

Three-node HA survives the failure of one node with no downtime, because etcd keeps quorum.

A full-cluster loss recovers in this order:

1. `tofu apply`, where it applies.
2. Machine-config apply and bootstrap.
3. Argo CD reconciles from git.
4. CNPG restores from PITR.

On pre-provided infrastructure the Talos nodes already exist, so recovery starts at the machine-config apply. Where the project operates the hypervisor, recovery starts with re-imaging the node disks.

This ADR decides the recovery objectives, not the runbook that runs them. They bind the backup retention, the Object Lock window, and the rehearsal cadence in [ADR-0207](0207-cluster-storage.md).

| Objective | Value | What sets it |
| --- | --- | --- |
| **RPO**: tolerated data loss | the WAL archive interval | CNPG's archiving cadence. A lower value costs archive volume, not architecture |
| **RTO**: restored and serving | under 30 minutes from the start of recovery | the four-step path above. Reconciliation from git takes most of the time |
| **Time to start recovering** | minutes in working hours, the next working day outside them | Nothing pages, per [ADR-0502](0502-alerting-and-on-call.md). [`reference/detection-latency.md`](../reference/detection-latency.md) holds the composed figure |

**Detection is outside RTO, and both rows bound an availability objective.** Without that boundary, the platform cannot honour a recovery objective outside working hours. A user's clock starts at the failure, not at the response.

The recovery is rehearsed quarterly with the backup restore drill in [ADR-0207](0207-cluster-storage.md). The rehearsal makes these values measurements, not intentions.

## Consequences

### Positive

- Three-node HA from day one removes the migration from a rebuild to HA.
- **Node configuration drift is impossible, not only mitigated.** The machine config is the node. No interface exists through which the two can diverge.
- **The node has no shell for a compromised process to reach.** The pods already had this posture. It now extends to the host under them.
- An OS upgrade is an image swap with a rollback. It is not a package transaction that can fail halfway.
- The same Kubernetes API runs end to end. Environments differ in detail, not in shape.
- Measurable conditions drive the growth triggers.
- Git reproduces provisioning, and OpenTofu is not a day-one dependency.

### Negative and Risks

- **Three nodes cost more than one.** Accepted: the alternative is a maintenance window that nobody wants to plan.
- **Self-hosted Kubernetes on plain compute is more operational work than managed Kubernetes.** The machine configuration holds the knowledge as code, and this reduces the risk.
- **There is no shell.** Debugging uses `talosctl`: logs, the dashboard, and the API. An engineer who reaches for `ssh` and `journalctl` has to learn a new loop. This is the cost of the property, not a defect.
- **Anything outside the base image is a build artefact.** A driver or kernel module becomes an Image Factory schematic and a custom installer image. It is pinned and tracked under [ADR-0113](0113-supply-chain-security.md), not installed with a package manager.
- **Nothing can run on these nodes outside Kubernetes.** A workload that must run beside the cluster cannot run here, and it needs its own host.
- **Nothing is bundled.** `local-path` is an installed component, not a shipped one. A deployment without a provider load balancer must choose one.
- **Talos is less widely operated than Debian.** Fewer community answers exist when something is strange, and the failure modes are less familiar. Accepted against the drift and escalation classes it removes.
- **`restricted` breaks third-party charts.** A community chart whose image runs as root or writes to its root filesystem does not schedule. The fix is a values override, a rebuilt image, or a separate `baseline` namespace. The failure shows at install, not at runtime, which is the intended direction. It still adds friction to every new platform component.
- **PSA's exception unit is the namespace, not the workload.** One component that needs privilege takes its whole namespace with it. So privilege partly sets the namespace layout, not only grouping. Kyverno could express exceptions per workload. This is the cost of not using it here.

## Rules

- Production runs on plain compute instances, never on managed Kubernetes. OpenTofu is a per-project tool. A project skips it where infrastructure is pre-provided or where the project operates the hypervisor itself.
- Where the project creates its own nodes, the creation steps and the image reference are committed with the inventory.
- Every node runs Talos Linux, configured only by its machine config. There is no SSH, no configuration-management agent, and no manual change to a node.
- Every environment runs three control-plane nodes with etcd on each. Workers are added when the resource-pressure trigger fires.
- Anything not in the base Talos image arrives as a system extension in a pinned installer image built through Image Factory.
- Every namespace carries the Pod Security Standards `restricted` labels with a pinned `enforce-version`. A namespace at `baseline` or `privileged` records the reason in its manifest. `(ref: Pod Security Standards; enforced: PSA)`
- Service containers run as non-root with a read-only root filesystem, `ALL` capabilities dropped, `allowPrivilegeEscalation: false`, and `seccompProfile: RuntimeDefault`. A writable path is an `emptyDir`. `(enforced: PSA)`
- A component that requires privilege runs in its own namespace and never shares one with a `restricted` workload.
- A new cluster bootstraps with the machine-config apply, then the Argo CD root Application. There is no configuration-management step between them and no further manual step.
- Growth beyond the day-one topology happens only when one of the documented triggers fires.
