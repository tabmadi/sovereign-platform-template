# staging platform secrets

The `staging-secrets` Application syncs this directory at sync-wave 1. The Application comes from the `secrets` ApplicationSet, per [ADR-0201](../../../../../docs/adr/0201-gitops.md). The base-tier sops-operator reconciles the `SopsSecret` CR here into native Kubernetes Secrets. The data and core platform tiers consume them, per [ADR-0202](../../../../../docs/adr/0202-secrets.md).

**The template ships this README, not the secret.** A template repo cannot carry real cluster secrets, and the `staging` cluster key in `.sops.yaml` is a placeholder. Until you add `platform.enc.yaml`, the Application syncs to zero resources: it is Healthy and empty. The platform charts that reference these Secrets stay in `CreateContainerConfigError`.

## Adopt

1. Generate the `staging` cluster age key.
2. Replace the `cluster_staging` placeholder in `.sops.yaml` with the public half of the key.
3. Put the private half in the cluster. See `docs/guide/secrets-runbook.md` and `infra/talos/README.md`. On Talos, the key goes in the SOPS-encrypted machine config as an inline manifest. Talos has no host filesystem to put it on.
4. **Replace the other two recipients of that path too.** `.sops.yaml` gives the path `eng_placeholder` and `ops_recovery` next to the cluster key. sops encrypts to every recipient of a rule, or to none. One remaining placeholder fails the encrypt with `malformed recipient`. The error names the placeholder, not the rule that added it.
5. Copy the skeleton below to `platform.enc.yaml`, and fill in real values.
6. Encrypt it in place: `sops --encrypt --in-place infra/gitops/platform/staging/secrets/platform.enc.yaml`. The `.sops.yaml` rule for this path encrypts only the `data` and `stringData` values, so the CR structure stays readable. It encrypts them to `cluster_staging`, the engineers, and ops-recovery.
7. Commit. Argo CD delivers the file, and the operator creates the Secrets.

## `platform.enc.yaml` skeleton

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: platform
  namespace: platform
spec:
  secretTemplates:
    # The S3 root credential that SeaweedFS uses, per ADR-0207. Every other
    # consumer below authenticates AS this identity. The store knows one root,
    # so it does not know a second key pair.
    - name: object-storage-root
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
        ADMIN_PASSWORD: ""
    # The registry's own logins, per ADR-0105. `htpasswd` has one BCRYPT line per
    # identity: a push identity and a pull identity. `consoleAuthorization` is the
    # `Basic` header that the console proxy sends for the browser.
    - name: zot-credentials
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
        htpasswd: ""
        consoleAuthorization: ""
    # The registry pull credential as a docker config, per ADR-0105. Every chart
    # that runs a first-party image names this Secret in `imagePullSecrets`. A
    # kubelet has no credential of its own, and the node cannot hold one.
    - name: registry-pull
      type: kubernetes.io/dockerconfigjson
      stringData:
        .dockerconfigjson: ""
    # The DNS-01 solver's credential, per ADR-0205. Without it, the public issuer
    # never becomes Ready, and no wildcard certificate is issued.
    - name: cloudflare-api-token
      stringData:
        token: ""
    - name: observability-bucket
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
    # CNPG's base backups and WAL archive, per ADR-0207. Without it, archiving fails. The WAL that CNPG cannot
    # ship grows on the primary's disk until the node is full.
    - name: postgres-backup-creds
      stringData:
        ACCESS_KEY_ID: ""
        SECRET_ACCESS_KEY: ""
    # `username` must be the role that `cluster.initdb.owner` names in the postgres
    # chart. Every DSN below uses the same string. Three places use one role.
    - name: postgres-superuser
      type: kubernetes.io/basic-auth
      stringData:
        username: ""
        password: ""
    # CNPG reconciles the read-only role's password from this Secret, per ADR-0401.
    - name: postgres-readonly
      type: kubernetes.io/basic-auth
      stringData:
        username: ""
        password: ""
    - name: temporal-db-creds
      stringData:
        password: ""
    - name: openfga-creds
      stringData:
        preshared_key: ""
        datastore_uri: ""
    - name: analytics-db
      stringData: { DATABASE_URL: "" }
    - name: catalog-db
      stringData: { DATABASE_URL: "" }
    - name: orders-db
      stringData: { DATABASE_URL: "" }
    - name: orgs-db
      stringData: { DATABASE_URL: "" }
    - name: payment-db
      stringData: { DATABASE_URL: "" }
    - name: kratos-secrets
      stringData:
        secretsDefault: ""
        secretsCookie: ""
        secretsCipher: ""
        dsn: ""
        # Non-production delivers to the sink, never to a recipient, per ADR-0307:
        #   smtp://mailpit.platform.svc.cluster.local:1025/?disable_starttls=true
        # An empty value falls back to the chart placeholder, which is a real
        # relay host. That is the one outcome the Rule forbids.
        smtpConnectionURI: ""
    # Only where this environment delivers mail and does not sink it, per ADR-0307.
    # The DKIM private half, whose public half is the committed `DKIM` record. And
    # the submission password, as the BCRYPT hash that maddy compares against.
    - name: maddy-dkim
      stringData:
        private.key: ""
    - name: maddy-submission
      stringData:
        password_hash: ""
    # Only when `hydra_thirdparty` is on, per ADR-0305. The Ory release deploys
    # Hydra next to Kratos. It reads all three keys from this Secret, because
    # `hydra.secret.enabled` is false in `infra/helm/platform/ory/values.yaml`.
    # `dsn` names the same owner role as every other DSN here, on the `hydra`
    # database. The chart's plaintext default has no password and is never read.
    # `secretsSystem` encrypts every issued token and consent record. To rotate
    # it, add a new value at the front. Remove the old value after the tokens
    # signed with it expire. A direct replacement invalidates all of them.
    - name: hydra-secrets
      stringData:
        secretsSystem: ""
        secretsCookie: ""
        dsn: ""
```

## `kyverno.enc.yaml` skeleton

Kyverno reads an image's signature from the registry that holds the image. It uses a credential from its own namespace, per [ADR-0104](../../../../../docs/adr/0104-supply-chain-security.md). The value is the `registry-pull` docker config above. A SopsSecret creates Secrets only in its own namespace. So this one is a second CR, not a second template in the first CR.

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: kyverno
  namespace: kyverno
spec:
  secretTemplates:
    - name: registry-pull
      type: kubernetes.io/dockerconfigjson
      stringData:
        .dockerconfigjson: ""
```
