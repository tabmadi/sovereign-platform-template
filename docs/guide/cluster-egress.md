# Cluster egress

Use this guide for the cluster and the machines of this platform at each egress level. The shared [egress guide](../egress.md) sets up each developer machine and each server first.

## Plan the network

- Use a proxy that accepts HTTPS CONNECT. Use a stable address that the host, Docker networks, Talos nodes, and pods can reach.
- Give those systems a direct route to their internal DNS resolver. The proxy resolves public names for proxied HTTP requests.
- Keep internal services direct. Add their hostnames and network ranges to `NO_PROXY`. Include the Kubernetes API, node addresses, pod and service ranges, and local domains.
- Allow direct access to internal Git, Zot, the Nix cache, and object storage. Include their full names even when their addresses fall inside an exempt range.
- Allow separate routes for protocols such as SSH, Talos management, NTP, and SMTP. Use an approved jump host or relay where needed.
- If the proxy inspects TLS, install its CA in each client that uses it. Include the host, Nix, Docker, BuildKit, images that fetch dependencies, nodes, and pods.

The proxy must allow the hosts in the lockfiles, the image references, and any redirects they use. Confirm the list for the roles you run.

| Role | Public destinations through the proxy |
| --- | --- |
| Workstation and runner | Nix installer and caches, flake sources, Forgejo or GitHub, package registries, chart repositories, and browser downloads |
| Docker daemon and BuildKit | Image registries, token endpoints, and registry blob hosts. Build steps also use Go, Bun, and npm sources. |
| Server provisioning | Nix caches and flake sources, Talos Image Factory, and any OpenTofu providers |
| Talos and Zot | Installer and Kubernetes images, the upstream image registries, and registry redirects |
| Argo CD | Git repositories and Helm chart sources |
| Enabled features | Model providers, external object storage, ACME and DNS provider APIs, and scanner databases |

Use an internal service when a firewall rule blocks a required public destination. If the proxy has no public route, follow [Run with internal sources](#run-with-internal-sources).

## Set up a developer workstation

1. Write the egress file of the machine, per the [egress guide](../egress.md).
2. Enter the dev shell and check the machine.
3. Start the full cluster.

```sh
nix develop
just egress-setup
just egress-setup --check
just cluster-up full
```

`just egress-setup` writes the Docker build settings. It also writes the drop-ins of the Nix daemon and Docker, and prints the commands that install them as root.

Each cluster command reads the egress file. kind gets the proxy, and the Argo CD repo-server gets the address that the kind network reaches. Run `just cluster-up full` after a change of the file.

Use a proxy address that Docker and Kubernetes reach. `127.0.0.1` inside a container points to the container. tabkit-ops replaces a loopback proxy with the gateway of each Docker network.

With `TABKIT_REGISTRY_MIRROR`, every image build takes its base images from the mirror. A Dockerfile mounts its Go modules and Bun packages from the Nix outputs `go-modules` and `bun-cache`, so a build step fetches nothing.

## Set up servers

### Forgejo, runner, and hypervisor

Every machine imports `infra/egress.nix`. Set the level, the proxy, and the mirrors there before you build the images. See [Setup modes](../reference/modes.md).

Use a proxy URL without credentials for runners that build pull request Dockerfiles. Build instructions can read proxy arguments. Use a restricted relay if the upstream proxy requires authentication.

For an internal Forgejo, set `enableAcme = false` in `infra/forge-host/settings.nix` before you deploy. Install the certificate chain and key at `/etc/forgejo/tls/fullchain.pem` and `/etc/forgejo/tls/key.pem`. Make them readable by the `forgejo` user and restrict access to the key. Install the site CA on Git clients, runners, and Argo CD.

At the internal and airgap levels, set `actionsUrl = "self"` in `infra/forge-host/settings.nix`. Mirror each action repository that a workflow names into the forge.

### Talos nodes

Put the proxy in a protected machine config patch. Pass it as a common `--config-patch` when you generate the [Talos machine configs](../../infra/talos/README.md). Apply it to every node before installation or bootstrap.

```yaml
machine:
  env:
    http_proxy: http://proxy.example.net:3128
    https_proxy: http://proxy.example.net:3128
    no_proxy: localhost,127.0.0.1,10.96.0.0/12,10.244.0.0/16,.svc,.cluster.local,kube.internal,registry.internal
```

Add the actual API endpoint, node addresses, and internal registries. Use an internal registry mirror for image pulls when the upstream registries need one. Stage the installer, Kubernetes images, and Cilium images before bootstrap if their sources are unavailable.

### Argo CD and workloads

Create a proxy Secret with the three uppercase keys from the host example. Include their lowercase forms for tools that use them. Use the protected secret flow from the [secrets runbook](secrets-runbook.md).

Create the Argo CD Secret in `argocd` before bootstrap. Pass a site values file to Argo CD with the following settings.

```yaml
argo-cd:
  repoServer:
    envFrom:
      - secretRef:
          name: outbound-proxy
```

```sh
ARGOCD_VALUES_FILE=/path/to/argocd-values.yaml \
  just argocd-bootstrap dev
```

Use the same values file for later runs of the bootstrap task. Use an internal Git origin for the bootstrap repository when one is available.
If the ApplicationSet controller calls a forge through the proxy, add the same Secret to `argo-cd.applicationSet.extraEnvFrom`.
For an internal Git server with a site CA, put its CA certificate under its hostname in `argo-cd.configs.tls.certificates`.
Follow the [GitOps bootstrap steps](gitops-runbook.md#bootstrap-a-deployed-environment) for the cluster age key.

| Workload | Setting in the environment values |
| --- | --- |
| Zot with upstream mirrors | Set `zot.proxySecretName` to the Secret in `platform`. |
| cert-manager with public TLS | Add the proxy keys from the Secret to `cert-manager.extraEnv` with `valueFrom.secretKeyRef`. |
| Other workloads with external dependencies | Set the chart's proxy or endpoint settings. Choose an internal endpoint if the client cannot use an HTTP proxy. |

Use site values for network policies. Add one rule for each workload that needs the proxy. The example permits Zot to reach one proxy address on TCP port `3128`. Match the real pod labels and update the IP when the proxy changes. Use an address from your own network.

```yaml
outboundProxyRules:
  - name: zot-outbound-proxy
    namespace: platform
    matchLabels:
      app: zot
    cidrs:
      - 192.0.2.10/32
    port: 3128
```

Apply the needed policy before first use if the namespace already has egress restrictions. For Argo CD, use `app.kubernetes.io/name: argocd-repo-server` in `argocd`.

Keep object storage, mail, and other internal dependencies on direct routes. Verify backups and restores with the chosen object storage. Restart affected pods after a proxy Secret change.

For public TLS, give cert-manager access to the CA and the DNS provider API through the proxy. Set `cert-manager.extraArgs` to use an internal recursive resolver for [DNS-01 checks](https://cert-manager.io/docs/configuration/acme/dns01/).

For site TLS, set `publicTls.enabled` to `false`. Use the site's issuer or provide the TLS Secrets `wildcard-tls` and `wildcard-ops-tls` in `platform`. Give clients the site CA.

## Run with internal sources

Use this path if the proxy cannot reach upstream sources. Use an import job with upstream access to stage the inputs. Mirror every pinned revision and image digest used by a job. Use the Nix installed on a self hosted runner.

1. Stage the OS packages and installers if provisioning also runs on the closed network.
2. Mirror the pinned Actions and point Forgejo and the workflows at the internal copies.
3. Configure the runner's Nix to trust the internal binary cache. Set internal endpoints for Actions cache and artifacts.
4. Set the Forgejo registry variables and credentials for internal Zot. Point Argo CD at internal Forgejo.

| Job | Inputs to import |
| --- | --- |
| PR checks | Locked flake sources, the dev shells, and Go, Bun, and Helm dependencies. Give Go commands outside Nix an internal module proxy. |
| Release and design preview | BuildKit, the Dockerfile frontend, base and copy stage images, Go modules, and Bun packages for the frontend and admin console. |
| Cluster, E2E, and Lighthouse | The image references in `infra/local/image-refs.txt`, kind, Zot, and Lighthouse images. Serve Helm subcharts and import the E2E shell with its Playwright browsers. Mirror the E2E packages in the root Bun lockfile. |
| Trivy scan | The vulnerability database and checks bundle. Refresh both on a schedule. Set `TRIVY_SKIP_DB_UPDATE`, `TRIVY_SKIP_CHECK_UPDATE`, and `TRIVY_OFFLINE_SCAN` to `true` for `just ci-scan`. |
| Scheduled jobs | Give `tabkit-ops ci-nightly-gate` a Forgejo endpoint. Run upstream discovery and public DNS checks on a network with access. |

Seed runner-local Zot from the internal registry before `cluster-up full`. Keep fonts in the frontend and load them with `next/font/local`. Record the source revision, lockfiles, image digests, and scanner snapshot for each import. Import new pins before jobs use them. A cache that fetches on a miss needs upstream access during the job. Test cache reads with public substituters disabled.

When measuring job time, use the same commit and equivalent runners. Record setup, dependency preparation, builds, cluster startup, and tests. Measure the import job and warm runs as well.

## Verify the path through the firewall

1. Start with a fresh worker or VM. Block direct public egress and keep the proxy and internal services reachable.
2. Run `just check` or `just ci`. Include a cold Nix build so cached dependency outputs cannot hide network failures.
3. Build and push a service, the frontend, and the admin image. Verify the image signatures and attestations.
4. Run `just cluster-up full`, `just verify`, `just e2e-install`, and `just e2e-smoke`. Run the full test and Lighthouse jobs for the roles you use.
5. Verify Argo CD sync, image pulls, and each enabled external service on the deployed cluster. Run the Trivy scan.
6. Check proxy and firewall logs. Confirm the public requests use the proxy and internal requests take their direct routes.

| Symptom | Check |
| --- | --- |
| Go or Helm fails inside Nix | Check the Nix daemon environment and repeat with the required output absent from the store. |
| Docker pulls work and BuildKit fails | Check the runner Docker CLI config and the proxy address reachable from the builder. |
| kind reports EOF while calling its API | Check the kind proxy environment and the API bypass. |
| A pod cannot resolve a public name | Check proxy reachability and test the HTTP request from the affected pod. Public DNS can be blocked when the proxy resolves the name. |
| Argo CD still shows a prior fetch failure | Check the repository from the repo-server. Run `argocd app get <app> --core --hard-refresh` after fixing access. |
| Talos waits for etcd during bootstrap | Check that the node can pull its installer and Kubernetes images. |
