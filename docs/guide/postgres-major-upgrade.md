# Postgres major-version upgrade

This guide gives the logical-replication cutover step by step. [ADR-0300](../adr/0300-data.md) holds the decision. This guide is the procedure.

Run it once for each Postgres release cycle, in a planned maintenance window. At cutover, every service has a short **read-only** window. No service goes offline.

## Why this upgrade is not in place

CNPG supports an in-place major upgrade. It rewrites the existing cluster and has no cheap rollback. If the new major fails, the old data directory is already converted. Logical replication keeps the old cluster running and serving until traffic moves. So **a rollback points the connection back to the old cluster**.

The cost: both clusters run at the same time. During the window, the node set needs spare capacity for two copies of the data.

## Before the window

1. **Read the release notes for the target major.** Read the incompatibilities section in particular. Logical replication does not carry sequences or large objects by itself. It also gives no warning about a change in behaviour.
2. **Check that every extension in use exists at the target major**, per [ADR-0300](../adr/0300-data.md). An extension without a package for the new major blocks the upgrade.
3. **Verify a restore.** The quarterly drill is the safety net if the cutover fails, per [ADR-0207](../adr/0207-cluster-storage.md). Do not run this procedure on a cluster whose last restore drill failed.
4. **Confirm that every table has a primary key.** Logical replication of `UPDATE` and `DELETE` needs a replica identity. Without one, a table does not replicate those rows, and nothing reports the failure.

## The cutover

```sh
# 1. Create the target cluster at the new major, in the same namespace.
#    Give it the size of the current one. It holds a full copy.
kubectl apply -f infra/helm/platform/postgres/  # with the new Cluster manifest

# 2. Wait until it reports healthy and empty.
kubectl -n platform get cluster postgres-<newmajor> -w

# 3. Start replication from the current cluster and wait for the initial sync.
#    Watch the lag until it stays near zero.
kubectl -n platform exec -it postgres-<newmajor>-1 -- \
  psql -c "SELECT * FROM pg_stat_subscription;"

# 4. Stop writes. Scale the service Deployments to zero, or put the edge
#    into maintenance. The read-only window starts here.

# 5. Confirm zero lag. Then advance the sequences on the target. Logical
#    replication does not carry them.

# 6. Point the services at the new cluster: update the connection secret,
#    and let the operator materialise it, per ADR-0202.

# 7. Scale the services back up. The read-only window ends here.

# 8. Verify: run the smoke suite, then watch the error rate and latency.
mise run e2e:smoke
```

## Rolling back

Before step 6, a rollback deletes the target cluster. Nothing has moved yet.

After step 6 and inside the window, follow these steps:

1. Point the connection secret at the old cluster.
2. Scale the services back up.

Writes that reached the new cluster after cutover are lost. For this reason, run the verification in step 8 immediately, not the next morning.

## After the window

- Keep the old cluster for at least one full backup retention period. Then delete it.
- Confirm that the first `ScheduledBackup` against the new cluster completes. Confirm that a PITR restore from it works. **A backup that nobody has restored is not a backup**, per [ADR-0200](../adr/0200-cluster-topology.md).
- Update the pinned major in the chart values. A fresh environment then builds at the new version.
