# Release runbook

How-to for cutting releases. The decision (Conventional Commits + cocogitto, tag per product, SemVer) is
[ADR-0013](adr/0013-release-and-versioning.md); this is the operational procedure.

## Model

- Commits follow Conventional Commits; cocogitto derives the version bump from commit types
  ([ADR-0013](adr/0013-release-and-versioning.md)).
- Versioning is SemVer, tagged **per product**, not one monorepo-wide version.
- Image tags are pinned by digest/SHA; floating tags are forbidden and gated by
  `mise run lint:floating-tags` ([ADR-0002](adr/0002-monorepo.md)).

## Cut a release

1. Ensure `master` is green (`mise run ci` / CI).
2. cocogitto computes the next version from the Conventional Commits since the last tag and updates the
   changelog.
3. Tag the product; CI builds and publishes the digest-pinned image.
4. ArgoCD rolls the new digest into the target environment ([docs/gitops/runbook.md](gitops/runbook.md)).

## Breaking changes

A breaking API change follows the API lifecycle in [ADR-0022](adr/0022-api-lifecycle.md): a new major
version path, a sunset header on the old version, and a deprecation window before removal. Contract
breakage is detected in CI ([ADR-0008](adr/0008-api-contracts.md)).

## Rollback

Roll back by pointing the environment at the previous digest (a Git revert of the image bump); ArgoCD
reconciles it ([ADR-0004](adr/0004-gitops.md)). Data migrations roll back via the migration's `down`
([docs/database/migrations.md](database/migrations.md)).
