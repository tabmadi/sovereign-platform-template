# ADR-0105: Image Registry

- **Status:** Accepted
- **Date:** 2026-08-06
- **Deciders:** Platform team
- **Related:** [ADR-0000](0000-platform-foundations.md), [ADR-0102](0102-source-control-and-ci.md), [ADR-0103](0103-release-and-versioning.md), [ADR-0104](0104-supply-chain-security.md), [ADR-0200](0200-cluster-topology.md)
- **Decides:** Images and their referrers live in zot, one instance per environment, backed by object storage.

## Context

Every deployable is a container image referenced by digest, per [ADR-0103](0103-release-and-versioning.md). [ADR-0104](0104-supply-chain-security.md) attaches a cosign signature, an SPDX SBOM, and SLSA provenance to each image, and Kyverno verifies them at admission. Those attachments are **OCI artifacts stored beside the image**. So the registry is part of the supply-chain control, not only a bucket that the pipeline pushes to.

At axis B maximal, the registry is a first-class decision. It also sits on the critical path of every node. During a scale-up or a node replacement, a registry outage stalls pod starts for any image that is not already cached.

## Decision drivers

1. **OCI 1.1 referrers**, so signatures, SBOMs, and attestations live with the image, per [ADR-0104](0104-supply-chain-security.md).
2. **Thinnest viable platform**, per principle 2 of [ADR-0000](0000-platform-foundations.md). The registry is one concern, and must not arrive with a datastore fleet.
3. **A pull depends on as little as possible.** Every node start reads the registry. So anything the registry is coupled to becomes a dependency of scheduling itself.
4. **Configuration in the repository**, per principle 1. Projects, quotas, and retention are files, not UI state.

Object storage as the backend, per [ADR-0207](0207-cluster-storage.md), is a platform constraint, not a driver. Every option below supports it. So it selects nothing, and it appears in the Decision instead.

## Considered options

| Option | Always-on workloads | OCI 1.1 artifacts | Config as files | Verdict |
| --- | --- | --- | --- | --- |
| **zot** | **one Go binary** | [native](https://zotregistry.dev/latest/), with S3-compatible storage | a single committed config file | **Chosen.** The only option that closes the concern without expanding the floor *(reasoned)* |
| Harbor | registry, registry controller, core, jobservice, portal, **its own Postgres, and a Redis** | yes | partly. Projects, robots, and retention are API and UI objects. Only a separate operator reconciles them | Feature-complete, and the reflex answer. Five workloads and two datastores for one concern is the purchase that principle 2 exists to refuse |
| [Project Quay](https://github.com/quay/quay) | registry, **its own Postgres, and a Redis**, with Clair beside it for scanning | yes | a config bundle, written through its own config tool | The same shape as Harbor under a different name. The scanning it brings is the gate that [ADR-0104](0104-supply-chain-security.md) already runs in CI |
| CNCF Distribution | one binary | yes. It is the reference implementation. The [referrers API](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#listing-referrers) arrived in its 3.x line. So the widely deployed 2.x images answer only through the fallback tag schema | one config file | The thinnest of all. It has no authentication model beyond htpasswd or a token service, no retention policy, and no UI. Each of those then becomes its own decision |
| Forgejo package registry | none, because the forge is already a decided component, per [ADR-0102](0102-source-control-and-ci.md) | partial | forge config | Free in component count, and still rejected. The reason is the coupling argument below, not capability |
| Managed registry | none | yes | provider API | Fails principle 3. It ranks late on the swap list of [ADR-0000](0000-platform-foundations.md), so it is a concession taken well after the ones above it |
| Do nothing | none | not applicable | not applicable | The honest baseline: images live wherever CI last pushed them. It is not compatible with digest-pinned admission |

Harbor loses on component weight, not on capability. Its replication, quota, and multi-tenancy features answer a problem that a single platform team with one registry does not have. Its Postgres and Redis are exactly the always-on floor cost that principle 2 is written to stop. Its Trivy scanner is optional and would stay off in any case, for the reason below.

**No bundled forge registry is eligible, whichever forge is chosen.** GitLab and Forgejo both ship one, so a bundled registry looks free in component count. It is not free. An artefact store inside the build system couples every pod start to forge availability. It also makes the system that produces an image the system that stores what vouches for it, against [ADR-0104](0104-supply-chain-security.md).

This separation lets [ADR-0102](0102-source-control-and-ci.md) hold that a forge outage does not stop the running system. It is also why the forge cannot settle the registry decision.

## Decision

| Concern | Decision |
| --- | --- |
| Registry | **zot**, one instance per environment, configured by a committed file |
| Storage backend | the object storage of [ADR-0207](0207-cluster-storage.md). Image data is never on a node volume |
| Artefacts | OCI 1.1 referrers hold the cosign signature, SBOM, and provenance from [ADR-0104](0104-supply-chain-security.md) |
| Authentication | pipeline credentials push and prune. Cluster credentials pull. Both are SOPS-encrypted, per [ADR-0202](0202-secrets.md). The pull credential reaches workloads as an `imagePullSecret`, not as node configuration. containerd 2 ignores the registry auth of the node once a hosts.d config path is set, and Talos always sets one, per [infra/talos](../../infra/talos/README.md) |
| Third-party images | pinned by digest, per [ADR-0104](0104-supply-chain-security.md). The `sync` extension of the registry serves them, and it mirrors every upstream that the platform pulls from |
| Retention | after each promotion, the pipeline deletes first-party tags that no environment's values pin and that none of the last ten commits name. It also deletes their signature and attestation tags. The garbage collection of the registry then reclaims the blobs on a schedule |

### Where the pipeline pushes

The registry that the pipeline pushes to is **configuration, not a constant**. A project generated from this template has a forge and no cluster. So the default is the own registry of the forge. A deployment that runs zot re-points the pipeline by setting two forge variables and two secrets. No workflow is edited.

| Setting | Default | Set it to |
| --- | --- | --- |
| `IMAGE_REGISTRY` | `ghcr.io` | the origin of the registry, per [ADR-0306](0306-trust-tiers-and-urls.md) |
| `IMAGE_REPOSITORY` | the forge repository path | the path that images live under |
| `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` | the own token of the forge | the push identity above |

The thin-YAML rule of [ADR-0102](0102-source-control-and-ci.md) buys the same property for build logic: a move is a re-target, not a rewrite. If the registry could only ever be the one of the forge, the pipeline would have to change when the platform gets its own registry.

**Scanning is not the job of the registry.** [ADR-0104](0104-supply-chain-security.md) makes it a merge gate in CI. zot can run a scanner. It stays off, so the concern stays in one place, per principle 5 of [ADR-0000](0000-platform-foundations.md).

### Mirroring the upstream registries

zot is also a **pull-through cache** for every upstream that the platform pulls from. On the local tiers, it is the **only** source:

- Each upstream is mirrored at the one address.
- No upstream is configured as a fallback endpoint.
- `cluster:up` fills the cache before it creates the cluster.

The reason is egress surface, not registry performance. Without a mirror, every layer that pulls an image has its own network configuration: each deployed node, each local kind node, and each build host. On a proxied network, one credential and one allow-list entry are then maintained once per puller. When one is missed, the failure never names the network. For example, a node reports `403 Forbidden` while fetching etcd and never bootstraps. Or Traefik sits in `ContainerCreating` while an upstream times out in the middle of the handshake. When every node points at zot, this becomes one component with egress and one firewall rule.

| Option | Verdict |
| --- | --- |
| **The `sync` extension of zot in `onDemand` mode, filled before the cluster** | **Chosen.** zot is already the registry, so this is configuration, not a component. One instance serves every upstream *(reasoned)* |
| `onDemand` alone, filled by the own pulls of the cluster | zot copies a whole image before it answers the manifest request that triggered it. So a cold pull costs tens of seconds. A bring-up asks for all its images at once. zot saturates, and every pull passes the containerd deadline. The pods back off while zot keeps caching images that nothing waits for. Most pods of a full tier sit in `ImagePullBackOff` against a registry that answers correctly. Re-derive this by emptying the cache directory and running `cluster:up full` *(measured)* |
| A push-filled mirror | It needs a list of images derived from the charts, and a hand-maintained list goes stale. An image that nobody adds falls back to the upstream, and the mirror bought nothing. A derivation that does not render the chart cannot see an image behind a conditional in that chart |
| `registry:2` as a pull-through cache | The obvious tool. It proxies exactly **one** upstream per instance, so each upstream is another registry to run |
| Per-node proxy configuration, no mirror | Correct. It is the same configuration repeated once per puller. Every copy must be right, and no copy says so when it is wrong |

**The local tiers run the same registry, as a host container.** The mirror on a laptop is zot, not a second product. So a developer gets the mirroring described above, and the image path is not a place where the environments differ, per [ADR-0205](0205-environment-parity.md). It sits beside the cluster, not inside it. The in-cluster instance stores its images in the object store. So it cannot serve the images that the pods of the object store need to start. Two deltas are local-only, and both are properties of a throwaway host container:

- Its storage is a directory, not a bucket.
- It serves anonymously. A credential on a laptop mirror guards nothing, and every pull would carry it.

**The in-cluster instance still runs on the full local tier, as an exercised chart, not as the registry of the node.** Every platform chart is applied there, so that the tier catches a chart change before a deployed environment, per [ADR-0205](0205-environment-parity.md). zot is no exception. It deploys, the local object store backs it, and it is reached at `zot.ops.<host>`. It is *not* the source that the nodes pull from. That is the host container above, because `*.localtest.me` does not resolve inside a node, per [ADR-0306](0306-trust-tiers-and-urls.md). [ADR-0205](0205-environment-parity.md) permits this node-provisioning delta.

So by default its catalogue is empty. An empty catalogue looks like a broken console, not like the parity artifact it is. So `cluster:up full` mirrors the first-party images into it after the platform is healthy. These are the same images that CI pushes to the in-cluster registry in a deployed environment. Its push path, object-store path, and console path are then exercised locally, not only in production. The nodes keep pulling from the host container. The in-cluster instance holds the same images, so only the one hop that the node networking forbids stays untested.

**The registry is in-cluster because of the placement rule** that [ADR-0207](0207-cluster-storage.md) states. A component lives off-cluster only where its data must outlive the cluster. The contents of the registry are reproducible: CI pushes them again, or they are read again from a surviving bucket. So the registry needs no independent survival. It stays in-cluster, where its object store already is. The backup store is the opposite case, and it goes off-cluster in production for exactly that reason.

**The cache is filled before the cluster exists, and the local nodes have no fallback.** `cluster:up` warms zot from a generated list, one image at a time, with nothing waiting on it. The nodes then read locally. A miss fails loudly and names the image. It does not become a slow direct pull that differs per machine.

A second upstream endpoint looks like a safety net, but it cannot act as one. containerd falls through to the next endpoint only on a fast failure. A saturated mirror fails by timing out, and that ends the pull. The only result is an image path that varies with the network, so no second endpoint is configured.

**This is not an authorization boundary.** The allow-list belongs to Kyverno, per [ADR-0104](0104-supply-chain-security.md), and that separation is deliberate. If a cache silently became an authorization boundary, nobody could safely flush it. Being the only *route* is a determinism property. What may run is still the question of admission.

**The warm list is generated, never written by hand.** This disqualifies the push-filled mirror above, not the mirroring itself. `mise run gen:image-allowlist` renders every chart and emits two outputs:

- the repository allow-list of Kyverno
- `infra/local/image-refs.txt`, the full references that the warm reads

One render gives both outputs, and CI checks them for drift. So the warm set cannot fall behind the charts. An image behind a conditional in a chart is as visible as any other.

**Docker Hub is `onDemand` only, and is never polled.** It rate-limits pulls and does not support catalog listing. So a scheduled sync walks a catalog that is not there, and spends the rate limit to find that out.

**This covers only image pulls, and not all of them.** `kind` downloads its node image through the docker of the host. The build path needs egress for base images and language modules. This does not touch traffic that is not images:

- chart repositories
- the git remote that Argo syncs
- ACME
- mail delivery
- DMARC reports

This reduces the number of layers that need a proxy. It does not remove the proxy or the network from a local bring-up.

## Consequences

### Positive

- One binary on the floor, in place of five workloads and two datastores.
- Registry durability is object-storage durability. A registry rebuild is a redeploy, not a restore.
- Signatures and SBOMs live with their images, so the admission check of [ADR-0104](0104-supply-chain-security.md) is a registry read.

### Negative and Risks

- **The registry is on the critical path for pod starts.** A registry outage stalls scale-ups and node replacements for uncached images. Statelessness backed by object storage mitigates this, because it makes recovery a redeploy.
- **zot is a younger project than Harbor**, with a smaller operator population. This is accepted under principle 4 on exit cost: images can be pushed again, and the OCI API is the interface. **The exit cost is not the whole cost.** The operator population is a second, independent price. No new engineer has debugged this component before. So the first incident is also the first hour that anyone spends inside it. [ADR-0200](0200-cluster-topology.md) openly accepts the same class of cost for Talos. It is paid at the worst moment, not at adoption.
- **The console reads. It does not administer.** The `ui` and `search` extensions of zot serve the catalogue at `zot.ops.<host>`, per [ADR-0306](0306-trust-tiers-and-urls.md). This shows what is in the registry without a shell. Projects, quotas, and retention stay committed files, and no screen writes them. Scripted inspection is a `crane` or `cosign` call. CVE scanning is a sub-key of the same extension, and it is off. It pulls a vulnerability database on a schedule, and scanning belongs to the merge gate, per [ADR-0203](0203-policy-enforcement.md).
- **The console does not ask for a second login.** The access policy of zot is one configuration for one process. Without a fix, a browser that passed the ops gate would meet the same htpasswd that the distribution API uses. An anonymous read policy would remove the prompt, but it would open every pull on `registry.<host>`. So the credential is presented for the browser instead. A small reverse proxy runs in the zot pod. It adds the `Authorization` header of the pull identity and serves the `zot.ops.<host>` origin, per [ADR-0306](0306-trust-tiers-and-urls.md). The `registry.<host>` origin still reaches zot directly, and its clients authenticate as before. The proxy adds the header on the console path only.
- **Robot credentials are long-lived** where the forge cannot mint short-lived ones. [ADR-0102](0102-source-control-and-ci.md) records the same constraint for signing identity.

### What would change this decision

| Change | Effect |
| --- | --- |
| The forge is replaced | **None.** No bundled forge registry is eligible, whichever forge it is, for the coupling reason above |
| Multi-tenancy, quotas, or replication becomes a requirement | **Decisive.** Harbor was rejected for carrying those capabilities. A need for one of them means the concern grew past what a single-instance registry answers |
| The registry needs an administrative console for a non-engineer | **Decisive.** The console above reads the catalogue. A surface that writes projects, quotas, or retention is the capability that Harbor was rejected for carrying |
| Scanning is wanted at the registry, not in CI | **None.** [ADR-0203](0203-policy-enforcement.md) assigns provenance to admission and scanning to the merge gate. A move here would be a policy-layer change, not a registry choice |
| The image estate outgrows one instance per environment | **None** on the component, and decisive on its topology. zot mirrors in the same config file, which is the recorded seam |

## Rules

- Images are stored in a self-hosted zot registry backed by object storage.
- Registry configuration is a committed file. Projects, quotas, and retention are never set through an API call or a UI.
- A first-party image tag is deleted once no environment's values pin it and it is outside the rollback window of the last ten commits. `(CI: ci:prune-registry)`
- The registry console is served at `zot.ops.<host>` behind the ops forward-auth. The own credentials of the registry gate the distribution API at `registry.<host>`, never an operator session, per [ADR-0306](0306-trust-tiers-and-urls.md).
- The registry of every environment is zot, including the local tiers. There it runs as a host container beside the cluster, per [ADR-0600](0600-local-development-loop.md). Anonymous access and directory storage are permitted there and nowhere else.
- The local nodes pull from that registry and from nowhere else. No upstream is configured as a fallback endpoint, and `cluster:up` warms the registry before it creates the cluster.
- The warm set is generated from the charts together with the allow-list of Kyverno, never written by hand. `(CI: lint:image-allowlist)`
- Signatures, SBOMs, and provenance are OCI referrers on the image they describe, per [ADR-0104](0104-supply-chain-security.md). `(ref: OCI 1.1)`
- Vulnerability scanning runs in CI, not in the registry.
- Forge variables set the registry that the pipeline pushes to. It is never written into a workflow.
- Deployments reference images by digest, per [ADR-0103](0103-release-and-versioning.md). `(enforced: Kyverno)`
