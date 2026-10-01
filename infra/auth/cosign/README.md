# The image-signing key pair

This key pair signs images, per ADR-0104.

`cosign.pub` is committed and **empty in the template**. `signing-key.enc.yaml` does not exist yet. One command creates both, once, at bootstrap:

```sh
mise run secrets:cosign
```

The command refuses while `.sops.yaml` still has placeholder recipients. A signing key encrypted to a placeholder is a key that nobody can decrypt.

## Why the public key is a committed file and not a values field

Every environment's Kyverno policy names this one file, delivered as a Helm `fileParameter`. The platform has one key pair and one copy of it, so there is one thing to review. A public key pasted into three environment values files is three copies that can disagree. The copy that disagrees is the one that stops verifying.

The file is committed **empty** and not absent. The reason is that the `fileParameter` is declared for every application in its tier. A path that does not exist fails all of them, not only this one. An empty file renders no policy. This is the correct state of a platform that has published nothing yet.

## Why the private half is not here

The private half is at `signing-key.enc.yaml`. SOPS encrypts it to the engineers, to ops-recovery, and to the CI identity. It is not encrypted to any cluster key. Kyverno verifies with the public half, so no cluster needs the private one. A secret delivered to a cluster is a secret that someone can make that cluster read.

CI decrypts it with an age key held as a forge secret, `SOPS_AGE_KEY_CI`, and then signs. The key exists as a file only inside a directory that `scripts/ci-sign.sh` removes when it exits.

## Rotation is not this command

Rotation has an order constraint. The policy must trust both public keys during the rotation window. If it does not, the cluster cannot restart images that it already runs. The six steps are in [`../../../docs/guide/secrets-runbook.md`](../../../docs/guide/secrets-runbook.md).
