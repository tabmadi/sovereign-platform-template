# Node machine configuration

Every node in a provisioned environment runs Talos Linux, and this directory is its configuration, per [ADR-0200](../../docs/adr/0200-cluster-topology.md). There is no SSH, no shell, no package manager, and no writable root filesystem. You configure a node when you apply a machine config document over its gRPC API. `talosctl` is the only other interface.

The result is that **node configuration drift is not reduced here. It is impossible.** The machine config is the node. Nothing converges it, because there is no second path by which the two could differ.

## What is here

| Path | What it is |
| --- | --- |
| `patches/common.yaml` | applied to every node, whatever its role |
| `patches/controlplane.yaml` | the control-plane role, on top of `common.yaml` |
| `patches/vip.yaml` | optional. A virtual IP for the control-plane endpoint, where no load balancer is in front of the API server |
| `patches/worker.yaml` | the worker role, applied when the scaling trigger of [ADR-0200](../../docs/adr/0200-cluster-topology.md) fires |
| `inventory/<env>/nodes.yml` | the addresses of pre-provided nodes, and the endpoint that clients dial |
| `schematic.yaml` | the [Image Factory](https://docs.siderolabs.com/talos/latest/learn-more/image-factory) recipe for the custom installer image |

## The two provisioning modes

ADR-0200 splits on provisioning, and **only** on provisioning. Everything after it is identical: machine configuration, Kubernetes, Cilium, and Argo CD.

**A project that owns its infrastructure** runs Terraform in `infra/terraform/`. Terraform creates the instances. Then it applies these same documents through the first-party `siderolabs/talos` provider. Machine-config apply and bootstrap become a plan, and not a script.

**A project that gets existing machines** does not use Terraform. It applies these documents to the nodes named in `inventory/<env>/nodes.yml`. Pre-provided means **pre-provided Talos**. A fleet that runs another system needs a reprovision, and not a configuration step.

## Applying

```sh
# Once per cluster: create the machine secrets, which are the cluster's identity.
talosctl gen secrets -o secrets.yaml
sops --encrypt --in-place secrets.yaml   # per ADR-0202: never committed in the clear

talosctl gen config example https://kube.dev.example.com:6443 \
  --with-secrets secrets.yaml \
  --config-patch @patches/common.yaml \
  --config-patch-control-plane @patches/controlplane.yaml \
  --config-patch-worker @patches/worker.yaml

talosctl apply-config --insecure -n 203.0.113.11 -f controlplane.yaml   # per node
talosctl bootstrap -n 203.0.113.11                                      # ONCE, one node
```

`bootstrap` initialises etcd. It runs on exactly one node, one time. If you run it on a second node, you make a second cluster.

## Two common failures

**`cni: none` does not remove flannel from a running cluster. Deleting the DaemonSets is also not enough.** Talos applies its default manifests once, at bootstrap, and then does not touch them. If you patch an existing cluster, the nodes come back `Ready` on flannel, while the config says that there is no CNI.

When you delete `kube-flannel` and `kube-proxy`, they are no longer reconciled. That does **not** undo what they already did to the node:

- Cilium disables flannel's CNI config by renaming it to `.cilium_bak`. The `flannel.1` interface stays.
- **kube-proxy's iptables NAT rules stay, and nothing maintains them.** Talos has no shell to flush them from, so a node reboot is the flush. Reboot the nodes one at a time, because they are etcd members.

**Verify with a POD, not with `cilium-dbg`.** A broken dataplane here reports itself as healthy. Take a converted cluster whose Cilium RBAC was deleted. Every agent kept serving from cached credentials. `cilium-dbg status` showed `KubeProxyReplacement: True`, `Cilium: Ok`, and `Cluster health: 3/3 reachable`. But no pod could reach a Service. The failure showed only as a symptom that looked unrelated: Argo CD's pre-install job timed out against `10.96.0.1:443`. Only a test pod showed the difference:

```sh
kubectl run t --image=busybox --restart=Never -- \
  sh -c 'wget -T10 -O/dev/null https://10.96.0.1:443/version; nslookup kubernetes.default'
```

**If you bootstrap with these documents from the start, none of this applies.** Neither flannel nor kube-proxy is ever created, so there is nothing to delete and nothing left behind. Only the conversion of a running cluster has this cost.

**Cilium's `k8sServiceHost` is KubePrism, not an API server.** It is `localhost:7445`, a per-node load balancer over every control-plane endpoint. So the agent survives the loss of the control plane that it pointed at. If you read `cilium-config` to check this, it shows an empty value and looks like a misconfiguration. Cilium 1.19 carries the address as the `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` environment variables on the agent, not in the ConfigMap.

## Planting the age key

A deployed environment's private age key is the root of trust for every secret that the platform decrypts, per [ADR-0202](../../docs/adr/0202-secrets.md). The sops-operator reads it from a Kubernetes Secret. There is no host filesystem to put it on, and no configuration-management agent to put it there. So it goes in the machine config itself, as an inline manifest:

```yaml
cluster:
  inlineManifests:
    - name: sops-age-key
      contents: |
        apiVersion: v1
        kind: Secret
        metadata:
          name: sops-age-key
          namespace: platform
        stringData:
          keys.txt: AGE-SECRET-KEY-<key>
```

This is not committed in the clear. The machine config that carries it is SOPS-encrypted like every other secret. That is the same protection that the key would have in any other place. It also means that the same apply recovers the cluster identity and the secret root of trust. No one has to remember a manual step during an incident.

## Pulling from the platform's own registry

The registry authenticates every pull, per ADR-0105. An anonymous client gets nothing. A **kubelet** is such a client. So every workload that runs a first-party image needs a pull credential. It comes as an `imagePullSecret` from the environment's `SopsSecret`, and that chart's values name it.

**The node cannot hold the credential instead, and the attempt looks like it worked.** Talos takes registry credentials in the machine config:

```yaml
machine:
  registries:
    config:
      registry.example.com:
        auth: { username: cluster, password: "<password>" }
```

Talos writes that correctly into the node's containerd configuration, but **containerd 2 ignores it**. Talos sets a `config_path` for hosts.d. Then containerd no longer reads the deprecated `registry.configs.*.auth` block, and hosts.toml has no field for credentials. The pull then fails with `no basic auth credentials`, on a node whose configuration contains them. `talosctl read /etc/cri/conf.d/01-registries.part` shows the unused password. Use the pull secret first.

## Behind a proxy

A Talos node inherits nothing from anyone's shell. On a proxied network, the node cannot pull, and **the failure never mentions the proxy**. The node reports `403 Forbidden` when it fetches `registry.k8s.io/etcd`, and etcd never leaves `Preparing`. Any process that waits on the cluster times out on `waiting for etcd to be healthy`. That looks like a broken cluster, and not like a blocked network. It is the most expensive way to learn this.

The proxy goes in the machine config, and only there:

```yaml
machine:
  env:
    http_proxy: http://proxy.example.com:8118
    https_proxy: http://proxy.example.com:8118
    # Without the CIDRs, the nodes send their own east-west traffic through the
    # proxy. That fails in a different way, and later.
    no_proxy: localhost,127.0.0.1,10.96.0.0/12,10.244.0.0/16,.svc,.cluster.local
```

Two details often cause problems:

- `127.0.0.1` is the NODE inside a node. A proxy on the operator's loopback must have an address that the node can route to.
- `no_proxy` must include the pod and service CIDRs. If not, the API server, the kubelet, and every pod-to-pod call go out through the proxy.

## Secrets

The machine secrets, the cluster CA and `talosconfig`, are SOPS-encrypted in git like every other secret, per [ADR-0202](../../docs/adr/0202-secrets.md). Git and those secrets can reproduce the cluster identity. That makes the loss of a full cluster recoverable: apply the configs, bootstrap, and let Argo CD reconcile.
