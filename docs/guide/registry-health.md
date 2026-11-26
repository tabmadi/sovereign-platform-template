# Registry health

This guide sets up the external registry probe and shows how to read the Registry health dashboard, per [ADR-0500](../adr/0500-observability.md).

## What each signal shows

| Signal | Shows | Does not show |
| --- | --- | --- |
| External probe | TLS and the response on the public path | why the path failed |
| Registry replicas | whether the pods report ready | whether a client can reach them |
| Node readiness | when a node stopped reporting | why it stopped |
| etcd latency | whether etcd writes reach the disk on time | which process used the disk |
| Host pressure | whether the hypervisor host ran short of CPU, memory, or I/O | which VM caused it |

## Set up the probe

The probe runs outside the workload cluster, so a failure includes the public path. In a Forgejo project, the runner is the vantage point.

1. Generate a password:

   ```bash
   PROBE_PASSWORD="$(openssl rand -hex 32)"
   ```

2. Store it as the `password` key of the `external-probe-auth` Secret, per the [secrets runbook](secrets-runbook.md).

3. Print the bcrypt hash of the password. Set `probe.enable` to `true` and `probe.passwordHash` to the hash in `infra/runner/settings.nix`. Then run `just runner-deploy`.

   ```bash
   nix shell nixpkgs#apacheHttpd --command htpasswd -nbBC 10 "" "$PROBE_PASSWORD" | cut -d: -f2
   ```

4. Set the probe in the values of the environment. Both the collector and the network policy read these keys:

   ```yaml
   externalProbe:
     enabled: true
     exporter: 10.0.10.40:9115
     cidr: 10.0.10.40/32
     targets: ["https://registry.example.com/v2/"]
   ```

An authenticated registry answers `401` to a request with no credential. The probe counts `200` and `401` as a good response.

## Alerts and retention

| Alert | Fires when | Severity |
| --- | --- | --- |
| `RegistryProbeFailing` | the probe fails for 5 minutes | page |
| `RegistryProbeMissing` | the exporter does not answer for 15 minutes | ticket |
| `EtcdMetricsMissing` | a member does not answer for 15 minutes | ticket |
| `EtcdWalFsyncSlow` | the p99 WAL fsync stays over 500 ms for 10 minutes | ticket |
| `EtcdBackendCommitSlow` | the p99 backend commit stays over 250 ms for 10 minutes | ticket |

Prometheus keeps these series for its normal retention, which `prometheus.retention` sets.

## Compare the signals during an incident

Open the dashboard, and set the time range around the first failure.

| Probe | Replicas | etcd or host | Likely cause |
| --- | --- | --- | --- |
| Failed | Ready | Normal | The public path: DNS, TLS, the edge, or the route |
| Failed | Not ready | Normal | The registry workload |
| Failed | Not ready | Slow | The disk or the host |
| OK | Ready | Slow | A slow disk that users do not feel yet |
| Unknown | Any | Any | The exporter or its network path. The registry can still be healthy |
