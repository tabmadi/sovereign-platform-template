# Disaster recovery runbook

This runbook recovers the platform after the loss of a full cluster. [ADR-0200](../adr/0200-cluster-topology.md) sets the recovery objectives and the backup design. This procedure meets them.

**Your RTO clock starts here, not at the failure.** ADR-0200 sets an RTO under 30 minutes from the start of recovery. It sets the RPO to the WAL archive interval. The time until someone notices the failure is a separate figure. [`reference/detection-latency.md`](../reference/detection-latency.md) holds it.

## Detection

**Nothing pages anyone.** Alertmanager routes a firing alert by its `severity` to email or to the webhook receiver, per [ADR-0502](../adr/0502-alerting-and-on-call.md). No escalation service is attached to that webhook. This is a decision, not a mistake. Outside working hours, expect to find an overnight incident in the morning. Plan the recovery window for that. [ADR-0502](../adr/0502-alerting-and-on-call.md) states the trigger that changes this position.

## Recovery

Run every command from the repository root. Step 1 applies only where the project provisions its own infrastructure. On hosts that are already provided, start at step 2.

```sh
# 1. Provision a new node set: instances, network, LB, DNS, firewall, bucket.
terraform -chdir=infra/terraform/environments/<env> apply

# 2. Apply the Talos machine configs, bootstrap the cluster, and add the
#    in-cluster age key. The target is the nodes from Terraform, or the
#    committed inventory of provided Talos nodes.
terraform -chdir=infra/talos/<env> apply

# 3. Lay the bootstrap floor and the root Application. Argo CD reconciles
#    everything else.
mise run argocd:bootstrap <env>

# 4. Restore Postgres from its archive. In the environment's platform values,
#    set `cluster.recovery.fromServer` to the lost cluster's archive name: its
#    `cluster.backup.serverName`, or `postgres` when unset. Give
#    `cluster.backup.serverName` a new name. CNPG does not archive into a path
#    that holds the WAL of another server. Commit, and wait for the healthy phase.
kubectl -n platform get cluster postgres -w
```

Steps 2 and 4 take most of the time. Step 3's reconciliation runs at the same time as step 4.

A running cluster refuses the new bootstrap and a smaller volume. To do step 4 on a live cluster, follow these steps:

1. Commit the values.
2. Run `kubectl -n platform delete cluster postgres`. This also deletes the cluster's volumes. Argo CD then recreates the cluster.
3. Remove `cluster.recovery.fromServer` when the cluster is healthy. If it stays set, the next recreation restores the old archive.

Rehearse this procedure every quarter against a staging rebuild. A Temporal `Schedule` tracks the rehearsals. **Record the elapsed time of each rehearsal.** The objectives in ADR-0200 are measurements. A rehearsal without a time leaves them as intentions only.

## Rehearsals

A step 4 time above 15 minutes, half the RTO, is the Longhorn trigger of ADR-0207.

| Date | Scope | Data | Step 4 elapsed | Result |
| --- | --- | --- | --- | --- |
