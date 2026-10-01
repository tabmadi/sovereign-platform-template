# The full tier runs through ArgoCD locally, per ADR-0201 and ADR-0600

`mise run cluster:up -- full` **is** the ArgoCD path. It does these steps in order:

1. It creates the cluster.
2. It installs the two components that ArgoCD cannot bootstrap: the CNI and ArgoCD itself.
3. It plants the SOPS age key.
4. It applies a local root-app from `infra/gitops/local-bootstrap/`.

The local root-app reconciles the same app-of-apps that prod uses, against committed **`master`** on the remote. This includes sync waves, `ApplicationSet` generators, and secret materialisation. CI's end-to-end job and the previews for each PR use this same path.

So the everyday full tier already exercises ArgoCD, and you do not need to turn anything on. Tests of **uncommitted** changes need a few extra steps. ArgoCD reconciles a git ref, not your working tree.

## Local bootstrap layout

`infra/gitops/local-bootstrap/` sits next to `bootstrap/`, not inside it. This is on purpose. The prod root-app runs `directory.recurse` over `bootstrap/`, so it never picks up the local-only appsets. The directory contains these items:

- a local root-app
- `local`-scoped copies of the platform and services `ApplicationSet`s
- `local`-scoped copies of the gateway and secrets apps

The local platform appset excludes Cilium and ArgoCD. The bootstrap installs them imperatively first.

## Testing uncommitted changes

### Service code: `cluster:add`

This is the fast path. Build your working-tree service into the cluster. It overrides the copy that Argo synced from the CI image:

```sh
mise run cluster:add -- catalog     # build → push to the local registry → helm upgrade (Argo auto-sync paused)
```

### Platform chart or values: `cluster:add`

```sh
mise run cluster:add -- ory         # working-tree helm upgrade, Argo auto-sync paused on that app
```

When you finish, turn GitOps on again for that app. The command prints the exact `kubectl patch`. Or run `cluster:up full` again.

### GitOps wiring: a branch

GitOps wiring means sync waves, ApplicationSets, and app definitions. `helm` cannot exercise the delivery path. So push a branch and point the local root-app at it. Only this kind of change needs a git round-trip:

```sh
git switch -c my-gitops-change
# edit infra/gitops/** ; commit ; push
git push -u origin my-gitops-change

# Point the local bootstrap at the branch. The root-app and the appsets'
# revision and targetRevision default to master. Then bring the full tier up:
sed -i -E 's/(revision|targetRevision): master/\1: my-gitops-change/' \
  infra/gitops/local-bootstrap/*.yaml
mise run cluster:up -- full
```

Revert the `sed` before you merge. `master` is the committed default. ArgoCD must be able to clone the repo. This template's repo is public, so a local run needs no credentials.

## CNI and CRD-operator changes, for example Cilium

For these changes, prefer a new cluster to an in-place upgrade. Run `mise run cluster:down -- full`, then a fresh `cluster:up -- full` **with** the change. A CNI swap on a live cluster interrupts networking for a short time. This comes from the component, not from a gap in the tooling.

## Troubleshooting: `local-root` never converges after `cluster:stop`

`cluster:stop` freezes cluster state. This includes any ArgoCD sync operation that is still `Running`. On resume, the controller attaches again to that operation. It reuses the task plan from the start of the operation, including sync waves. It ignores what the manifests say now. So a sync that started before a fix to a wave annotation never converges, and `argocd app wait` times out.

- `cluster:up full` repairs this itself. After the first wait times out, `scripts/cluster.sh` terminates the stuck operation. It then forces a fresh sync, which computes the plan again against current git. Only after that does the task fail.
- Outside that path, run `argocd --core app terminate-op <app>`, then `argocd --core app sync <app>`.
