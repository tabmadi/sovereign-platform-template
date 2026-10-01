# Working behind an HTTP proxy

Proxy configuration belongs to **your machine**, not to this template. The repo carries no proxy values and no proxy logic. After the one-time steps below, the `cluster:*` tasks work with no change. On a network without a proxy, none of this applies.

**Most of the image-pull steps below are optional.** zot mirrors docker.io, quay.io, ghcr.io, and registry.k8s.io as a pull-through cache, per [ADR-0105](../adr/0105-image-registry.md). When zot is up, the cluster nodes fetch images from it, not from the internet. So one component needs egress, not every node.

The **build** path still needs a proxy: base images, Go modules, and bun. Traffic that is not an image, such as ACME, also needs it. So steps 1 and 2 concern your host and your builds. Step 3 matters only before the mirror exists.

The steps expect a **loopback** proxy on your host, for example `http://127.0.0.1:8118`. Each step is read from a different place: the host, a build container, the cluster node, or a cluster pod. So the address differs in each step. This is the only difficult part. A **routable** proxy address works from everywhere. Use it unchanged in every step, and ignore the address notes of each step.

## Start here

```sh
mise run proxy:setup              # apply everything that does not need root
mise run proxy:setup -- --check   # what is configured, what is missing, and the exact fix
```

The task reads the live state, not the intent. It checks these points:

- what the docker daemon reports
- what is in your `~/.docker/config.json`
- whether the cluster node can resolve names
- whether the repo-server carries the proxy

It computes the address for each step for you and names the step that is wrong. On a direct network, it exits 0 and reports that none of this applies.

Only step 1 needs root, because it edits a systemd unit. `--fix` writes that file for you and prints the two `sudo` lines to paste. The task applies everything else itself.

Read the rest of this page to learn *why* a step exists. Also read it when the doctor reports a problem that it cannot fix. The steps below are the reference. The command above is the path.

## Step 1: Proxy the Docker daemon, for image pulls

The daemon runs on your host, so a loopback proxy stays `127.0.0.1`. Create `/etc/systemd/system/docker.service.d/http-proxy.conf`:

```ini
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:8118"
Environment="HTTPS_PROXY=http://127.0.0.1:8118"
Environment="NO_PROXY=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7,.svc,.svc.cluster.local,127.0.0.1,localhost,.localtest.me"
```

Then run `sudo systemctl daemon-reload && sudo systemctl restart docker`.

## Step 2: Proxy Docker builds

Docker injects `proxies.default` from `~/.docker/config.json` into the RUN steps of `docker build`. There the reader is **inside a container**. In a container, `127.0.0.1` is the container itself. So use the **IP of the docker-bridge gateway**. Find it with:

```sh
docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}'    # usually 172.17.0.1
```

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://172.17.0.1:8118",
      "httpsProxy": "http://172.17.0.1:8118",
      "noProxy": "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.svc,.svc.cluster.local,127.0.0.1,localhost,.localtest.me"
    }
  }
}
```

Keep the package and image registries **out** of `noProxy`, so they route through the proxy. A loopback value here is the typical build failure. The package manager inside the build cannot see the proxy and connects directly. The firewall then blocks it.

## Step 2b: DNS for the daemon's embedded resolver

At start, the Docker daemon caches the nameservers from the host's `/etc/resolv.conf`. The embedded DNS of every container forwards external names to that cached set. Then the host's resolver can change, for example through a new gateway or an `nmcli` switch. After that, every container loses external resolution with no warning, and this includes the kind node. `docker exec <node> getent hosts github.com` returns nothing, while the host resolves the name. Docker's embedded DNS still answers container names, such as `registry.localhost` and the node's own hostname. So the failure looks like a cluster problem, but it is not.

The fix is of the same kind as step 1: restart the daemon once, so it reads the current resolver again. Before you blame anything else, verify that the embedded DNS forwards to the expected place:

```sh
docker exec <node> getent hosts github.com    # empty while the host resolves → stale upstream
sudo systemctl restart docker
```

Until the daemon restarts, you can unblock a running cluster node by node. Point the node at a working resolver. Write the registry container names into its `/etc/hosts`. Docker does not rewrite an edited resolv.conf:

```sh
node=$(kubectl --context kind-${CLUSTER:-platform} config view --minify -o jsonpath='{.clusters[0].cluster.server}')
docker exec "${CLUSTER:-platform}-control-plane" sh -c \
  'printf "nameserver 1.1.1.1\n" > /etc/resolv.conf'
reg_ip=$(docker inspect registry.localhost \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' | cut -d' ' -f1)
docker exec "${CLUSTER:-platform}-control-plane" sh -c \
  "echo '$reg_ip registry.localhost' >> /etc/hosts"
kubectl --context kind-${CLUSTER:-platform} -n kube-system rollout restart deploy/coredns
```

The restart is the durable fix. The `/etc/hosts` entry lasts only until the node is recreated.

## Step 3: The environment that `cluster:up` runs kind in

`mise run proxy:setup` writes `infra/local/proxy.local.env`, and `scripts/lib/cluster.sh` loads it. So every cluster command runs with this machine's egress, and no cluster script names a proxy. The file is local to the machine and gitignored. You export nothing by hand:

```sh
mise run cluster:up -- full
```

**The file exists because kind reads the proxy variables from its own environment.** The node's kubeadm calls the API server *by name*: `https://<cluster>-control-plane:6443`. No CIDR in a `NO_PROXY` list exempts a hostname. So that call goes to the proxy and fails. Only kind can prevent this. When kind sees the variables, it takes them over and appends what the node needs, including the node's own name.

```text
no_proxy=fc00:f853:ccd:e793::/64,172.19.0.0/16,localhost,127.0.0.1,10.96.0.0/16,
         10.244.0.0/16,<cluster>-control-plane,.svc,.svc.cluster,.svc.cluster.local
```

Without the variables, the node still gets a proxy. The docker CLI injects `proxies.default` from `~/.docker/config.json`, from step 2, into every container it creates. But that value has no node name, and `kind create` stops partway through:

```text
✗ Starting control-plane 🕹️
ERROR: failed to create cluster: failed to remove control plane taint: ...
Get "https://<cluster>-control-plane:6443/api?timeout=32s": EOF
```

The address in this file is the **host's** address, because everything that reads the file runs on the host. Images are not affected either way. `cluster:up` fills the local zot before it creates the cluster, and the nodes pull only from there, per [ADR-0105](../adr/0105-image-registry.md). So a proxy that cannot reach an upstream fails during warming and names the image. It does not fail as an `ImagePullBackOff` twenty minutes into a sync.

## Step 4: Proxy Argo CD's repo-server, for git and chart repositories

`mise run proxy:setup` writes this setting to `infra/local/proxy.local.yaml`. Every `cluster:up -- full` applies it when it installs Argo CD. The setting is a file, not a `kubectl patch`, for this reason: the repo-server does not exist until the first full tier starts. A fix that only patches a running Deployment fixes the *second* start and hangs the first. The file is local to the machine and gitignored. The address is your host's docker gateway.

Steps 1 to 3 get **images** into the cluster. They do nothing for a workload that opens its own connection to the internet. Argo CD's repo-server is such a workload. To render a chart with `dependencies:`, it runs `helm repo add` against each upstream repository from inside the pod. Preloaded images do not help, because no image pull is involved.

The failure is quiet and easy to blame on the wrong cause:

- The app reports `Unknown` with a `ComparisonError`. Its running workloads stay `Healthy`.
- The repo-server also clones the git remote. So on a network that blocks the remote, the root app never renders. The tier stops before any application appears.
- If the app is a wave gate, the root app-of-apps waits behind it. The whole tier then looks stuck, for a reason far from the tier.

```text
ComparisonError  Failed to load target state: ... error building helm chart dependencies:
                 failed to add helm repository https://k8s.ory.sh/helm/charts: ...
                 failed running helm: `helm repo add ...` failed timeout after 1m30s
```

The sign that the proxy is the cause and not the chart: the **same command succeeds on your host**. Your shell exports the proxy, and the pod does not. Do not conclude that the repository is down or that the URL moved. Compare like with like, and run the command in the pod:

```sh
pod=$(kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-repo-server \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n argocd exec "$pod" -- helm repo add probe <repo-url>   # hangs, then times out
```

Here the reader is **a pod**. So a loopback proxy needs the **gateway of the kind network**:

```sh
docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}'   # take the IPv4
```

Set the proxy through the chart's `repoServer.env`. `infra/helm/platform/argocd` wraps the upstream `argo-cd` chart. So the key sits under the subchart alias. Helm ignores a bare `repoServer.env` with no warning and renders no env. This is machine config, so keep it out of the committed values file. Pass it at upgrade time, or from an untracked overlay. Quote every `--set`. Otherwise the shell globs the `[0]`.

```sh
helm upgrade argocd infra/helm/platform/argocd -n argocd --timeout 8m \
  --set 'argo-cd.repoServer.env[0].name=HTTPS_PROXY' \
  --set 'argo-cd.repoServer.env[0].value=http://172.19.0.1:8118' \
  --set 'argo-cd.repoServer.env[1].name=HTTP_PROXY' \
  --set 'argo-cd.repoServer.env[1].value=http://172.19.0.1:8118' \
  --set 'argo-cd.repoServer.env[2].name=NO_PROXY' \
  --set-string 'argo-cd.repoServer.env[2].value=localhost\,127.0.0.1\,.svc\,.svc.cluster.local\,.cluster.local\,10.0.0.0/8\,.localtest.me'
```

Confirm that helm rendered the setting. Do not read the live Deployment for this. A manual `kubectl set env` survives the 3-way merge, so the Deployment shows your own patch in both cases:

```sh
helm get manifest argocd -n argocd | grep -A1 'name: HTTPS_PROXY'
```

`NO_PROXY` must keep traffic inside the cluster direct. Without it, the repo-server calls the API server and its own services through the proxy. Verify with the same `helm repo add` in the pod. It returns in about one second. Then force Argo to discard what it cached while the network was broken:

```sh
argocd app get <app> --core --hard-refresh
```

A plain `--refresh` is not enough. Argo caches the generation error with the manifests. So the app reports the old `ComparisonError` word for word long after the fix. This looks like a failed fix.

### Do not change CoreDNS

The symptom suggests a DNS fix. A chart repo on GitHub Pages resolves to four anycast addresses. A network that drops traffic to some of them fails about half the time. Two DNS changes seem to help, but neither is the fix:

- pinning the good addresses in a CoreDNS `hosts` block
- suppressing AAAA with a `template ANY AAAA { rcode NOERROR }` stanza

**When the proxy is set, the pod never connects to those addresses itself.** The proxy resolves the name and connects for the pod. So the address that the cluster resolves no longer matters. A test removed both stanzas and verified this. The repo-server then resolved the chart host to IPv6 only. The AAAA stanza existed to prevent exactly that condition. `helm repo add` still returned in 1 to 3s.

Keep in CoreDNS only what the platform put there. For the inner loop, that is the `dev.localtest.me` `rewrite stop` blocks from `scripts/lib/cluster.sh`. Argo cannot see live Corefile edits. They do not survive a rebuild, and they stay after the problem is gone. If you already made such edits, remove them and verify again. A workaround that nobody can explain is worse than the fault it hid.

The removal has one side effect. A CoreDNS rollout kills lookups in progress. So unrelated apps briefly go `Unknown` with `failed to list refs: ... EOF` against GitHub. The rollout causes this, not the removal. Confirm it with `git ls-remote` from inside the repo-server. Then clear it with `--hard-refresh`, for the same caching reason as above.

All the steps above read a local kind node. Both local tiers use kind, per [ADR-0600](../adr/0600-local-development-loop.md). So only the node name differs between them.

## Talos nodes: the machine config, not the shell

This section covers **deployed** environments, per [ADR-0200](../adr/0200-cluster-topology.md). No local tier applies a machine config.

The steps above configure a kind node, which gets much of its setup from the host docker daemon. A Talos node gets nothing from the host. It has no shell, no daemon configuration, and no environment to export into. The proxy is part of the machine config, or it does not exist.

```yaml
machine:
  env:
    http_proxy: http://10.5.0.1:8118
    https_proxy: http://10.5.0.1:8118
    no_proxy: localhost,127.0.0.1,10.96.0.0/12,10.244.0.0/16,.svc,.cluster.local
```

Three points often cause errors. All three come from a measurement, not a guess:

**`127.0.0.1` is the node.** A node cannot reach a proxy on your host's loopback by that address. Use an address that the node can route to. On real hardware, that is a routable address.

**`no_proxy` must carry the pod and service CIDRs.** Without them, the kubelet, the API server, and every call between pods go out through the proxy. That fails later than a missing proxy, and in a different way.

**The failure never mentions the proxy.** Without the proxy config, a node reports `403 Forbidden` on the fetch of `registry.k8s.io/etcd`. etcd never leaves `Preparing`. The bootstrap times out on `waiting for etcd to be healthy`. This looks like a broken cluster, not a blocked network. A measurement found this, at a high cost in time.

## Stalled image pulls

A slow proxy makes a cold registry slow. zot copies a whole image before it answers the request that triggered the copy. If the cluster starts the pulls, this is fatal. Every pod asks at the same time, zot saturates, and each pull goes past containerd's deadline. A warm-up before the cluster starts prevents this. The warm-up always runs: `cluster:up` does it on every network.

If a warm-up fails, it names the images that it could not cache. It stops before it creates a cluster. Run it again. It skips cached images in microseconds, so a retry only fetches what is still missing.

## Restricted registries

Some networks have a registry that blocks **digest** pulls, so only tags resolve. On such a network, pre-pull the platform images by tag, and load them with `kind load docker-image`. The upstream charts pin images by digest, per [ADR-0104](../adr/0104-supply-chain-security.md), and that is what fails.

`kind load` works on both tiers, so this recovery is the same everywhere. Pass `--name` to reach the cluster of the full tier.
