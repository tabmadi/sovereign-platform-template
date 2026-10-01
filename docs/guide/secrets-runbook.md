# Secrets runbook

This guide shows how to manage secrets. [ADR-0202](../adr/0202-secrets.md) holds the decision: SOPS and age, the sops-operator, and encrypted secrets in Git. This guide is the operational procedure.

## Model

- Secrets are committed **encrypted** with SOPS and age. The private age key of a deployed environment never enters Git. The in-cluster sops-operator decrypts the secrets into Kubernetes Secrets, per [ADR-0202](../adr/0202-secrets.md).
- The local tier's private key is the exception, and it is committed. No bootstrap step materialises a key for a disposable cluster. The key decrypts local values only, per [ADR-0205](../adr/0205-environment-parity.md).
- No secret is ever committed in plaintext. No secret is set by a click in a UI, per principle 3 of [ADR-0000](../adr/0000-platform-foundations.md).

## Generate or rotate the age key

```sh
mise run secrets:age            # generates the local age key material
```

Locally, the key is disposable, and the bootstrap plants it, per [ADR-0205](../adr/0205-environment-parity.md). In a deployed environment, the age private key reaches the cluster out-of-band. It is the root of trust for decryption. Treat its loss as an event that rotates every secret.

## Edit a secret

1. Decrypt the file in place with SOPS, edit it, and encrypt it again. SOPS does this as one transaction on save.
2. Commit the encrypted file. ArgoCD and the sops-operator reconcile it into a Kubernetes Secret, per [ADR-0201](../adr/0201-gitops.md).
3. Never paste the decrypted value into a chart values file. Review and `mise run lint:auth-inline` both guard against inlined secrets.

## Rotate a leaked secret

1. Change the credential at its source, for example a DB password or a bucket key.
2. Update the SOPS file, encrypt it again, and commit.
3. Roll the workloads that use it, so they pick up the new Kubernetes Secret.
4. If the private age key itself may be exposed, rotate the age key too.

**For the object store, step 1 is a real step.** SeaweedFS creates its S3 identity from `object-storage-root` on FIRST START. After that, the store owns the identity. A re-encrypted Secret changes what the consumers send, never what the store accepts.

Nothing fails at rotation time. Every running consumer holds the old key in an environment variable and keeps working. The failure comes later, one workload at a time. Each workload restarts for an unrelated reason and gets `SignatureDoesNotMatch`. Its neighbours still use the same store with no error.

So change the identity in the store in the same step. Roll every consumer, not only the one you work on.

## Rotate the image-signing key

The cosign key pair signs every first-party image. Kyverno verifies the signature at admission, per [ADR-0104](../adr/0104-supply-chain-security.md). This is the one rotation with a required order. The policy that trusts the key also blocks every deploy when the key is wrong.

**The policy carries both public keys through the window.** Images signed with the old key are already running. Any reschedule admits them again. If you remove the old key before those images are gone, the cluster cannot restart its own workloads.

1. **Generate the new pair.** Encrypt the private half with SOPS to the cluster age key. Commit both halves: the public one in plaintext, the private one encrypted.
2. **Add the new public key to the `ClusterPolicy` as a second attestor**, and merge. The policy now accepts either key. Confirm that the Application is synced before you continue.
3. **Point CI at the new private key** and merge. Every image built after this point is signed with the new key.
4. **Rebuild and roll every running image.** This step takes the most time. The window stays open until the cluster cannot schedule any image signed by the old key. This includes any image that a node replacement pulls.
5. **Remove the old public key from the policy** and merge.
6. **Delete the old private key** from the SOPS file.

**Do not merge steps 2 and 5.** A policy that trusts only the new key blocks admission across the cluster while old-signed images are still schedulable. That is row 5 of [`../reference/risk-register.md`](../reference/risk-register.md), caused on purpose. If it happens, the break-glass is the kubeconfig path below, plus removal of the webhook configuration.

**If the private key may be exposed**, you cannot extend the window. Steps 4 and 5 are the incident. Until step 5 lands, an attacker with the old key can sign an image that the cluster admits.

## Break-glass

[break-glass](break-glass.md) covers cluster recovery when the auth plane is down. It also describes the optional second break-glass path: local-admin credentials sealed in SOPS.
