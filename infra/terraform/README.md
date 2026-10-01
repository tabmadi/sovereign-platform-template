# Terraform: per project, not on day one

The template's day-one path assumes **pre-provided nodes**, per ADR-0200. The machine configs under `infra/talos/` are applied to hosts that already run Talos. A committed inventory names them: `infra/talos/inventory/<env>/nodes.yml`. There is **no default Terraform run**, and Terraform creates no bucket. Loki and Tempo durability and CNPG backups point at an existing S3-compatible bucket, by endpoint and credentials. The credentials come from SOPS-decrypted Secrets, per ADR-0202.

**The production object store works the same way, on purpose**, per [ADR-0207](../../docs/adr/0207-cluster-storage.md). It must be outside the cluster's failure domain, and the template ships no module to create it. A module names a provider, and that would choose a cloud for every adopter. Instead, ADR-0207 states the requirements that the bucket must meet. Meet them with Terraform, a console, or a rack.

`terraform` stays available as a latent tool in `.mise.toml`. A project that provisions its **own** infrastructure adds a provider module here and connects it:

```text
infra/terraform/
  modules/<provider>/   # for example hetzner, aws, or gcp: the machines, network, and DNS
  environments/<env>/   # backend config and a module block per environment
```

A project that provisions its own infrastructure also gets the first-party [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/latest) provider. It applies the machine configs and bootstraps the cluster as part of the plan. That is the real difference between the two modes. The cluster is the same. The machine-config apply becomes a planned resource, and not a command that someone runs.

In both modes, the node addresses go in `infra/talos/inventory/<env>/nodes.yml`. `talosctl` and `lint:naming` both read that file.
