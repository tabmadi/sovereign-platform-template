# Disaster recovery runbook

Recovering from full cluster loss. The recovery objectives and the backup design are [ADR-0200](../adr/0200-cluster-topology.md); this is the procedure that meets them.

**Your RTO clock starts here, not at the failure.** ADR-0200 commits to under 30 minutes from the start of recovery, and RPO to the WAL archive interval. How long it took anyone to notice is a separate figure, and it is in [`reference/detection-latency.md`](../reference/detection-latency.md).

## Detection

**Nothing pages anyone.** Alertmanager routes a firing alert to email or to the webhook receiver by its `severity` ([ADR-0502](../adr/0502-alerting-and-on-call.md)), and no escalation service is attached to that webhook. This is a decided position, not an oversight: out of hours, expect to find an overnight incident in the morning, and plan the recovery window accordingly. [ADR-0502](../adr/0502-alerting-and-on-call.md) states the trigger that buys this down.

## Recovery

Run every command from the repository root. Step 1 applies only where the project provisions its own infrastructure; on pre-provided hosts, start at step 2.

```sh
# 1. Provision a new node set — instances, network, LB, DNS, firewall, bucket.
terraform -chdir=infra/terraform/environments/<env> apply

# 2. Apply the Talos machine configs and bootstrap the cluster, plus the
#    in-cluster age key. Runs against the Terraform-produced nodes, or the
#    committed inventory of pre-provided Talos nodes.
terraform -chdir=infra/talos/<env> apply

# 3. Lay the bootstrap floor and the root Application; Argo CD reconciles
#    everything else.
mise run argocd:bootstrap <env>

# 4. Restore Postgres from its archive. In the environment's platform values set
#    `cluster.recovery.fromServer` to the lost cluster's archive name (its
#    `cluster.backup.serverName`, or `postgres` when unset) and give
#    `cluster.backup.serverName` a new one: CNPG will not archive into a path that
#    holds another server's WAL. Commit, and wait for the healthy phase.
kubectl -n platform get cluster postgres -w
```

Steps 2 and 4 dominate the wall clock, and step 3's reconciliation overlaps step 4.

A running cluster refuses the new bootstrap and a smaller volume, so step 4 on a live cluster is: commit the values,
then `kubectl -n platform delete cluster postgres`, which takes its volumes with it, and Argo CD recreates it. Drop
`cluster.recovery.fromServer` once the cluster is healthy: left set, the next recreation restores the old archive.

Rehearsed quarterly against a staging rebuild, tracked as a Temporal `Schedule`. **Record the elapsed time of each rehearsal**: the objectives in ADR-0200 are measurements, and a rehearsal that does not time itself leaves them as intentions.

## Rehearsals

A step-4 time above 15 minutes, half the RTO, is ADR-0207's Longhorn trigger.

| Date | Scope | Data | Step 4 elapsed | Result |
| --- | --- | --- | --- | --- |
