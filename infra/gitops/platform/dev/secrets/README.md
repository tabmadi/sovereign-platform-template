# dev platform secrets

This directory is synced by the `dev-secrets` Application (the `secrets` ApplicationSet, [ADR-0201](../../../../../docs/adr/0201-gitops.md), sync-wave 1). The base-tier sops-operator reconciles the `SopsSecret` CR here into native Kubernetes Secrets that the data + core platform tiers consume ([ADR-0202](../../../../../docs/adr/0202-secrets.md)).

**The template ships this README, not the secret.** A template repo cannot carry real cluster secrets, and the `dev` cluster key in `.sops.yaml` is a placeholder. Until you add `platform.enc.yaml` below, the Application syncs to zero resources (Healthy, empty) and the platform charts that reference these Secrets stay in `CreateContainerConfigError`.

## Adopt

1. Generate the `dev` cluster age key and replace the `cluster_dev` placeholder in `.sops.yaml` with its public half; plant the private half in-cluster (see `docs/guide/secrets-runbook.md` and `infra/talos/README.md` — on Talos it rides in the SOPS-encrypted machine config as an inline manifest, because there is no host filesystem to place it on).
2. **Replace the other two recipients of that path as well.** `.sops.yaml` gives it `eng_placeholder` and `ops_recovery` beside the cluster key, and sops encrypts to every recipient of a rule or to none — one remaining placeholder fails the encrypt with `malformed recipient`, naming the placeholder rather than the rule that pulled it in.
3. Copy the skeleton below to `platform.enc.yaml`, fill in real values, and encrypt it in place: `sops --encrypt --in-place infra/gitops/platform/dev/secrets/platform.enc.yaml`. The `.sops.yaml` rule for this path encrypts only `data`/`stringData` values (the CR structure stays readable) to `cluster_dev` + engineers + ops-recovery.
4. Commit. Argo delivers it and the operator materialises the Secrets.

## `platform.enc.yaml` skeleton

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: platform
  namespace: platform
spec:
  secretTemplates:
    # The S3 root credential SeaweedFS is configured with (ADR-0207). Every other
    # consumer below authenticates AS this identity: the store knows one root, so
    # a second key pair is a key the store has never heard of.
    - name: object-storage-root
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
        ADMIN_PASSWORD: ""
    # The registry's own logins (ADR-0105): `htpasswd` carries one BCRYPT line per
    # identity — a push identity and a pull identity — and `consoleAuthorization`
    # is the `Basic` header the console proxy presents for the browser.
    - name: zot-credentials
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
        htpasswd: ""
        consoleAuthorization: ""
    # The registry pull credential (ADR-0105), as a docker config. Every chart
    # running a first-party image names this Secret in `imagePullSecrets`; a
    # kubelet has no credential of its own and the node cannot hold one.
    - name: registry-pull
      type: kubernetes.io/dockerconfigjson
      stringData:
        .dockerconfigjson: ""
    # The DNS-01 solver's credential (ADR-0205). Without it the public issuer
    # never becomes Ready and no wildcard certificate is ever issued.
    - name: cloudflare-api-token
      stringData:
        token: ""
    - name: observability-bucket
      stringData:
        AWS_ACCESS_KEY_ID: ""
        AWS_SECRET_ACCESS_KEY: ""
    # `username` has to be the role `cluster.initdb.owner` names in the postgres
    # chart, and the same string every DSN below uses. Three places, one role.
    - name: postgres-superuser
      type: kubernetes.io/basic-auth
      stringData:
        username: ""
        password: ""
    # CNPG reconciles the read-only role's password from this Secret (ADR-0401).
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
        # Non-production delivers to the sink, never to a recipient (ADR-0307):
        #   smtp://mailpit.platform.svc.cluster.local:1025/?disable_starttls=true
        # Leaving this empty falls back to the chart placeholder, which is a real
        # relay host — the one outcome the Rule forbids.
        smtpConnectionURI: ""
    # Only where this environment delivers rather than sinking (ADR-0307). The DKIM
    # private half, whose public half is the committed `DKIM` record; and the
    # submission password as the BCRYPT hash maddy compares against.
    - name: maddy-dkim
      stringData:
        private.key: ""
    - name: maddy-submission
      stringData:
        password_hash: ""
    # Only when `hydra_thirdparty` is on (ADR-0305). The Ory release deploys
    # Hydra beside Kratos and reads all three keys from this Secret, because
    # `hydra.secret.enabled` is false in infra/helm/platform/ory/values.yaml.
    # `dsn` names the same owner role every other DSN here does, against the
    # `hydra` database; the chart's plaintext default carries no password and is
    # never read.
    # `secretsSystem` encrypts every issued token and consent record, so rotate
    # it by prepending a new value and dropping the old one once the tokens
    # signed under it have expired — replacing it outright invalidates them all.
    - name: hydra-secrets
      stringData:
        secretsSystem: ""
        secretsCookie: ""
        dsn: ""
```

## `kyverno.enc.yaml` skeleton

Kyverno reads an image's signature from the registry the image lives in, with a credential from its own namespace ([ADR-0104](../../../../../docs/adr/0104-supply-chain-security.md)). The value is the `registry-pull` docker config above; a SopsSecret materialises in its own namespace, so this one is a second CR rather than a second template in the first.

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
