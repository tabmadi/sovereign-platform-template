#!/usr/bin/env bash
# Cut a repo-wide CalVer release (ADR-0103). A release is the production deploy:
# dev and staging deploy continuously from master, and production moves only when
# someone runs this.
#
#   mise run release            # compute, stamp, changelog, commit, tag, push
#   DRY_RUN=1 mise run release  # everything except the commit, tag, and push
#
# cocogitto is changelog-only here: it does not compute the version. CalVer comes
# from the date and the last release tag, because the only question asked of a
# release version is when it shipped.
set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
# shellcheck source=lib/yaml.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/yaml.sh"

dry_run="${DRY_RUN:-}"

# ── 1. Compute the next CalVer ────────────────────────────────────────────────
# vYYYY.0M.MICRO. Same month bumps MICRO; a new month resets it to 0.
year="$(date -u +%Y)"
month="$(date -u +%m)"
last="$(git tag -l 'v[0-9][0-9][0-9][0-9].[0-9][0-9].*' --sort=-v:refname | head -1)"

micro=0
if [[ -n "$last" ]]; then
  last_ym="${last%.*}"     # v2026.08
  last_micro="${last##*.}" # 3
  if [[ "$last_ym" == "v${year}.${month}" ]]; then
    micro=$((last_micro + 1))
  fi
fi
version="v${year}.${month}.${micro}"

# Helm and npm both require SemVer, and SemVer forbids a leading zero in a numeric
# identifier — so `2026.08.0` is rejected where `2026.8.0` is accepted. The stamped
# fields carry the normalised form; the tag and the image label carry the CalVer.
semver="${year}.$((10#$month)).${micro}"

step "releasing ${version} (previous: ${last:-none})"
detail "stamped version fields: ${semver}"

if git rev-parse --verify --quiet "refs/tags/${version}" >/dev/null; then
  fail "${version} already exists — a release tag is immutable"
fi

# ── 2. Stamp the version fields a build tool requires ─────────────────────────
# A chart's `version` is its own; `appVersion` names the upstream release for a
# wrapper chart and is only stamped where it already tracks the chart's version,
# which is what makes a chart first-party.
shopt -s nullglob globstar
for chart in infra/helm/**/Chart.yaml; do
  chart_version="$(yq '.version // ""' "$chart")"
  app_version="$(yq '.appVersion // ""' "$chart")"
  yaml_set_scalar "$chart" ".version" "$semver" || true
  if [[ -n "$app_version" && "$app_version" == "$chart_version" ]]; then
    yaml_set_scalar "$chart" ".appVersion" "$semver" || true
  fi
done
detail "stamped $(find infra/helm -name Chart.yaml | wc -l) chart(s)"

stamped_pkg=false
for pkg in apps/*/package.json; do
  [[ "$(jq -r 'has("version")' "$pkg")" == "true" ]] || continue
  tmp="$(mktemp)"
  jq --arg v "$semver" '.version = $v' "$pkg" >"$tmp" && mv "$tmp" "$pkg"
  stamped_pkg=true
  detail "stamped $pkg"
done

# The lockfile records every workspace member's version, so stamping a manifest
# without refreshing it leaves the two disagreeing — and the drift check compares
# the tree against what the generators produce, so it fails on the release commit
# itself. Measured on v2026.09.0: `bun.lock` still carried apps/frontend at 0.1.0.
#
# `--lockfile-only` because the release stamps versions; it does not resolve
# dependencies, and a release that silently installed something new would be a
# release nobody reviewed.
if [[ "$stamped_pkg" == true ]]; then
  bun install --lockfile-only >/dev/null
  detail "refreshed bun.lock"
fi

# The template's own release stamp, carried in the tree rather than in the tag
# (ADR-0106). A repository the forge creates from this one is a squashed copy with
# no history and no link back, so the ref it forked from has to be a file it
# carries; `project:init` reads it to write `_commit`. Stamped with the CalVer tag
# rather than the SemVer fields above, because that is what a git ref resolves.
echo "$version" >.template-version
detail "stamped .template-version"

# ── 3. Regenerate the changelog ───────────────────────────────────────────────
# One top-level CHANGELOG.md, committed, so a reviewer sees what the release will
# say and it survives a shallow clone or a mirror.
step "rendering CHANGELOG.md"
cog changelog >CHANGELOG.md
ok "CHANGELOG.md written ($(wc -l <CHANGELOG.md) lines)"

# ── 4/5. Commit, tag, push ────────────────────────────────────────────────────
if [[ -n "$dry_run" ]]; then
  warn "DRY_RUN set — not committing, tagging, or pushing"
  detail "would commit: chore(release): ${version}"
  detail "would tag:    ${version}"
  detail "the stamped fields, bun.lock and CHANGELOG.md are left in the working tree to inspect;"
  # .template-version needs both verbs because it is untracked before the first
  # release and tracked after it — `git checkout` cannot restore a file git has never
  # seen, and `rm` on the tracked one deletes the stamp a generated project reads.
  # A project generated from this template is always in the first case: `_exclude`
  # drops the file, so its own first release creates it fresh.
  detail "  git checkout infra/helm apps/*/package.json bun.lock CHANGELOG.md   discards them"
  detail "  git checkout .template-version 2>/dev/null || rm -f .template-version"
  exit 0
fi

git add -A
git commit -m "chore(release): ${version}"
git tag -a "$version" -m "$version"
git push origin HEAD "refs/tags/${version}"
ok "released ${version}"
