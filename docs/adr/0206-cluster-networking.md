# ADR-0206: Cluster Networking

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0200](0200-cluster-topology.md), [ADR-0203](0203-policy-enforcement.md), [ADR-0304](0304-identity-and-authorization.md), [ADR-0305](0305-edge-auth-and-traffic-policy.md), [ADR-0500](0500-observability.md), [ADR-0501](0501-operator-uis-and-dashboards.md)
- **Decides:** Cilium is the CNI from bootstrap, with WireGuard encryption and default-deny in both directions, and no service mesh runs above it.

## Context

[ADR-0200](0200-cluster-topology.md) puts Talos on plain instances and removes the host's attack surface. Neither Talos nor Pod Security Admission limits which pod may open a connection to which. That question is settled at bootstrap, because **a live cluster cannot hot-swap its CNI.**

The answer is load-bearing beyond networking. Internal calls carry forwarded identity headers and no token, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). So the network policy, not the service, guarantees that only sanctioned callers reach a service's port.

This ADR decides three things: the CNI, the postures that are on from day one, and whether a service mesh runs above the CNI. [ADR-0305](0305-edge-auth-and-traffic-policy.md) covers traffic that reaches the cluster from outside. [ADR-0203](0203-policy-enforcement.md) decides which layer enforces which class of invariant.

## Decision drivers

1. **The pod network is not a trust boundary by default.** The CNI decides whether a compromised pod can reach Postgres.
2. **The concession on header trust needs a network guarantee.** [ADR-0305](0305-edge-auth-and-traffic-policy.md) accepts that a service trusts `X-User-Id`, because default-deny limits who can send it. A weaker network weakens an accepted risk in another place.
3. **One primitive per concern**, per principle 5 of [ADR-0000](0000-platform-foundations.md). Encryption, identity, L4 policy, and flow visibility are the job of one component, or of four.
4. **Nothing on the hot path per service**, per [ADR-0000](0000-platform-foundations.md). A proxy per pod is a cost multiplied by the service count.

## Considered options

### East-west security

**Neither layer next to the CNI provides east-west security.** A service mesh sits above the CNI and runs on it. Talos's own networking sits below it, on the host. So the day-one decision is at the CNI layer, compared on security capability. Linkerd is the mesh column, because it is the lightest mesh. A mesh that loses these rows in its best case loses them in every case.

**Talos's networking is scoped to the node.** The [host firewall](https://docs.siderolabs.com/talos/latest/networking/host-firewall) governs the node's own ports: kubelet, etcd, and the API server. It never sees traffic between pods. KubeSpan encrypts links between nodes. It segments nothing, and it does not touch pod traffic on the same node. Both harden the machine. Driver 1 is about the network between pods.

| Capability | flannel only | Calico, eBPF dataplane | flannel with KubeSpan and Calico | flannel with Linkerd | **Cilium with WireGuard** |
| --- | --- | --- | --- | --- | --- |
| Components to operate | 1 | 1 | **3** | 2 | **1** |
| L3 and L4 default-deny segmentation | **none. A flat network** | all pods | all pods | meshed app traffic only | all pods |
| Protection of the data tier: Postgres, object storage, and OpenFGA | fully open | NetworkPolicy | NetworkPolicy | only if the data tier is meshed, and the bootstrap with many Jobs works against that | NetworkPolicy |
| Cryptographic workload identity | none | none | none | mTLS certificates, meshed pods only | label identity. SPIFFE is an option later |
| Encryption in transit, east-west | **plaintext** | all pods, WireGuard | only between nodes | meshed pods only | all pods, WireGuard |
| Services without kube-proxy | no | yes, in the eBPF dataplane | **no. Policy-only mode uses iptables** | no | yes |
| L7 authz by route and method | none | limited, and based on Envoy in the paid tier | none | fine-grained | coarse, through Envoy |
| Egress control, DNS and FQDN, metadata SSRF | none | CIDR egress. **FQDN is in the paid tier** | CIDR egress | not a Linkerd concern | FQDN and L3 egress in the open distribution |
| Per-flow visibility | none | **metrics for denied packets. Flow logs are paid** | none | meshed pods only | Hubble, from the same datapath |
| Verdict | The API server accepts policy, and nothing enforces it | **Runner-up.** This platform commits to both capabilities that it puts behind a paywall | the most components and the fewest capabilities | Scoped to the mesh. It adds to a CNI and does not replace one | **Chosen** *(reasoned)* |

**flannel ships no NetworkPolicy controller.** So the API server accepts a policy, and nothing enforces it. This is worse than no policy, because it gives false confidence.

**Calico is the runner-up.** Its open distribution matches three capabilities: segmentation, WireGuard encryption of all pod traffic, and kube-proxy replacement through eBPF. Two capabilities it puts behind a paywall are load-bearing here:

- FQDN egress. Without it, a policy falls back to hand-maintained CIDR lists for each external dependency.
- The per-flow surface. [ADR-0501](0501-operator-uis-and-dashboards.md) commits to it as this ADR's audit trail.

Calico's iptables dataplane is a benefit, because any engineer can inspect it. The eBPF mode that drops kube-proxy gives up that benefit.

**flannel with KubeSpan and Calico is the Talos-native path plus policy, and it costs the most for the least.** Calico over flannel runs in policy-only mode, so the dataplane is iptables and kube-proxy stays. KubeSpan requires the [discovery service](https://docs.siderolabs.com/talos/latest/configure-your-talos-cluster/system-configuration/discovery). Its hosted endpoint makes east-west encryption depend on a third party at runtime. Its self-hosted build has a commercial licence. Both fail principle 3 of [ADR-0000](0000-platform-foundations.md).

**Cilium wins on breadth.** Its extra controls map onto the most frequent cluster attacks: lateral movement to the data tier, and credential theft through the metadata endpoint. It also covers CNI, Services, encryption, and observability as one component.

### Why no service mesh

**A mesh runs over a CNI, never in place of one.** So the question is not Cilium or a mesh. It is Cilium, or Cilium plus a mesh. The mesh brings a second identity system and a second encrypted datapath on the same nodes. The alternative is one config flag in Cilium.

**Sidecars do not decide it.** Linkerd puts a proxy container on the hot path of every pod, against driver 4. Istio's ambient mode removes that proxy. In ambient mode, a ztunnel on each node carries L4 and mTLS, and waypoint proxies are added only where L7 policy is needed. The overlap below rules out ambient mode anyway.

| What a mesh adds | Who needs it | This platform |
| --- | --- | --- |
| L7 traffic management: weighted routing, mirroring, and circuit breaking | progressive delivery by percentage | No delivery by traffic split is committed. **This is the trigger that reopens the row**, and it is the one capability here that Cilium lacks |
| L7 authorization imposed from outside the application | large estates in many languages, and code that cannot change | Oathkeeper at the edge and OpenFGA in the app, per [ADR-0305](0305-edge-auth-and-traffic-policy.md) and [ADR-0304](0304-identity-and-authorization.md) |
| Per-request telemetry for workloads without instrumentation | applications without tracing | Every service is instrumented, per [ADR-0500](0500-observability.md) |
| Certificate identity per workload | any of the three conditions that [ADR-0305](0305-edge-auth-and-traffic-policy.md) records against its concession on header trust | label identity. Cilium mutual auth and SPIFFE are available later, without sidecars |
| A multi-cluster fabric with locality failover | one service across clusters | one cluster per environment |

**FQDN egress stays a CNI job in both cases.** Istio's `ServiceEntry` with `REGISTRY_ONLY` matches on SNI and Host. This is policy for a cooperating workload, not enforcement against a compromised one. Driver 1 asks for control in the datapath, and Cilium provides it in every column.

## Decision

### Cilium is the CNI from bootstrap

The [machine config](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium) sets `cluster.network.cni.name: none` and `cluster.proxy.disabled: true`. So Talos ships neither its default CNI nor kube-proxy, and Cilium provides both.

Cilium arrives as an inline manifest in the machine config, not as a later install. A node reports `NotReady` until a CNI runs, and a cluster without one reboots to try again. So delivery with the bootstrap removes a timed race. After that, Argo CD adopts the release for upgrades.

**A live cluster cannot hot-swap its CNI.** So the security posture is set at bootstrap and never added later.

### Three Talos properties are invariants, not preferences

| Constraint | Consequence |
| --- | --- |
| Workloads may not load kernel modules | `SYS_MODULE` is dropped from Cilium's default capability set |
| kube-proxy is absent | Cilium gets the API server host and port directly, because no in-cluster Service exists to discover it through |
| **[KubeSpan](https://docs.siderolabs.com/talos/latest/networking/kubespan) is not enabled** | Talos's own WireGuard mesh intercepts traffic between nodes. Cilium's eBPF datapath expects that traffic on the primary interface. The result is asymmetric routing and broken pod traffic across nodes. East-west encryption is done once, by Cilium |

KubeSpan needs this second statement. Enabling it looks like more encryption, but it causes an outage across nodes.

### Three postures, on from day one

| Posture | Mechanism |
| --- | --- |
| **Default-deny segmentation** | The `platform-baseline` CiliumNetworkPolicy sets `enableDefaultDeny` for ingress and egress across every platform pod. All allows add to it. Each service's chart declares which callers may reach it |
| **Encryption in transit** | `encryption.type: wireguard` encrypts all east-west pod traffic between nodes. It is a config flag, not a component |
| **Egress control** | With default-deny egress, no pod reaches the internet unless a policy grants it. A clusterwide policy also denies `169.254.169.254/32`. So a future broad egress grant cannot become an SSRF path to instance credentials |

Default-deny is load-bearing, not only defence in depth. It is what makes driver 2 hold.

### Traffic flow through the cluster

```text
Internet
  │
Provider Load Balancer  (L4, one stable public IP per env)
  │
Traefik  (TLS via cert-manager, L7 routing, rate limiting)
  ├── <host>/api/*                        ─▶ Oathkeeper ─▶ backend service   (ADR-0305)
  ├── <host>/(landing|panel|devportal)/*  ─▶ frontend pod                     (ADR-0400)
  ├── lowdefy.ops.<host>/                 ─▶ Oathkeeper ─▶ Lowdefy            (ADR-0401)
  ├── grafana.ops.<host>/                 ─▶ Oathkeeper ─▶ Grafana            (ADR-0501)
  └── hubble.ops.<host>/                  ─▶ Oathkeeper ─▶ Hubble UI          (ADR-0501)
```

**Traefik is the only ingress. Oathkeeper is an auth filter behind it, not a second gateway**, per [ADR-0305](0305-edge-auth-and-traffic-policy.md). The default stack has no API-management gateway.

**DNS.** One wildcard `A` record per environment points at the load-balancer IP. cert-manager requests one wildcard certificate per environment through DNS-01. `external-dns` is not used, because the wildcard covers new services.

**The zone is declared in the repository and applied from it** by [dnscontrol](https://docs.dnscontrol.org/), through `mise run dns:apply`. A wildcard leaves few records, and few records make the whole zone declarable. The file states every record, and the apply deletes every record that the provider holds and the file does not. The alternative is a zone that states intent while a console holds the truth. That is the drift that every other part of this platform refuses. `external-dns` stays unused. It reconciles records for Kubernetes objects, and the wildcard leaves none to reconcile.

Terraform owns DNS where a project provisions through a provider, per [ADR-0200](0200-cluster-topology.md). Where a project operates its own hypervisor and runs no Terraform, dnscontrol owns the zone.

| Option | State to keep | Runtime cost | Verdict |
| --- | --- | --- | --- |
| **dnscontrol** | none: the zone file is the state, and each run reads the provider | a pinned binary, run on demand | **Chosen.** It is one Go binary on a toolchain that is already Go. Its deletion logic runs across many more zones than this platform holds *(reasoned)* |
| OctoDNS | none, with the same model | a Python runtime that this repository does not pin | The nearest equivalent. It is the right answer for a project that already carries Python or spans several providers. Recorded as the runner-up |
| Terraform's provider | a state file per zone, kept somewhere and never lost | none beyond the binary | It brings back the tool that the hypervisor mode drops, for a few records. A lost state file leaves the zone harder to recover than the file that describes it |
| A script against the provider API | none | none | Deletion is the one operation where custom code is hardest to justify. The failure is silent, remote, and hard to reverse |
| The provider's console | none committed | none | The truth lives where no reviewer sees it. That is the drift this ADR refuses |

So two provider capabilities are requirements, not conveniences. Both are verified before an environment is provisioned:

- **A DNS provider API that cert-manager supports.** Without it, DNS-01 issuance has no path.
- **Reverse-DNS `PTR` delegation on the mail egress IP.** [ADR-0307](0307-outbound-email.md) needs it to match maddy's HELO name. Not every provider offers it. Where a provider offers it, it is often manual, only on request, or unavailable for load-balancer addresses.

Both are cheap to confirm when the provider is chosen, and expensive to discover later. A missing `PTR` shows as mail rejected at the first send, not as a failed deploy.

### Observability of the network

Hubble provides per-flow visibility, and it is the audit surface for these policies. It works through the CLI, the drop metrics in Grafana, and the auth-gated UI, per [ADR-0501](0501-operator-uis-and-dashboards.md). Grafana covers application observability, per [ADR-0500](0500-observability.md).

Cilium covers CNI and mesh as one component. Its eBPF datapath without sidecars gives transparent encryption, L7 policy, and per-flow observability with no injected proxy. Cilium mutual auth and SPIFFE can add certificate identity later, without sidecars.

## Consequences

### Positive

- One component provides CNI, Services, east-west encryption, egress control, and flow visibility. This meets driver 3 in fact, not only in argument.
- The header trust of [ADR-0305](0305-edge-auth-and-traffic-policy.md) rests on a network guarantee, and the datapath enforces it. So it constrains a compromised pod, not only a cooperating one.
- No proxy runs per pod, so the security posture costs nothing per service.
- No future egress grant can reach a metadata-endpoint SSRF, because the deny is clusterwide, not per policy.

### Negative and Risks

- **Cilium is harder to debug than flannel.** It uses eBPF programs, `cilium status`, and the Hubble CLI. The committed chart and Argo CD upgrades after bootstrap reduce the risk.
- **The CNI is set at bootstrap and cannot change on a live cluster.** For this reason the posture is decided here and not deferred. For the same reason, the exit is a cluster rebuild, not a values change.
- **No L7 traffic management.** Weighted routing, mirroring, and circuit breaking are unavailable. Their adoption means the adoption of a mesh. The trigger is a committed requirement for progressive delivery.
- **KubeSpan is a trap with a friendly name.** It looks like more encryption, and it breaks pod traffic across nodes. Nothing in the Talos configuration surface warns about the interaction.

## Rules

- The CNI is Cilium from day one. It is delivered as an inline manifest in the machine config and adopted by Argo CD for upgrades. Talos ships neither its default CNI nor kube-proxy.
- KubeSpan is not enabled. East-west encryption is Cilium's WireGuard. Both together break pod traffic across nodes.
- Talos's host firewall governs the node's own ports. It is never treated as pod-to-pod segmentation.
- `SYS_MODULE` is dropped from Cilium's capability set, and the API server host and port are set explicitly.
- Default-deny is enforced for ingress and egress across every platform pod. All allows add to it. `(enforced: CiliumNetworkPolicy)`
- WireGuard transparent encryption is on for all east-west pod traffic. Plaintext east-west traffic is not shipped.
- A clusterwide policy denies `169.254.169.254/32`, so no egress grant can become a metadata-SSRF path. `(enforced: CiliumNetworkPolicy)`
- Cilium NetworkPolicy is the internal trust boundary between services, and each service declares its allowed callers. `(CI: lint:service-contract)`
- No dedicated service mesh is deployed, with sidecars or ambient. A mesh runs over the CNI, not in place of it. So a mesh is a second component that provides encryption, identity, and L4 policy again, after Cilium. The edge and the app already cover its L7 layer.
- Each environment has one wildcard `A` record and one wildcard certificate. `external-dns` is not used.
- Every record in every zone that the project owns is declared in `infra/dns/` and applied from it. A record created in the provider's console does not survive the next apply. `(CI: dns.yml)`
- An environment is provisioned only where the provider offers a DNS API that cert-manager supports and `PTR` delegation on the mail egress IP.
