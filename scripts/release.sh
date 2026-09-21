#!/usr/bin/env bash
# Cut a repo-wide CalVer release (ADR-0103). A release is the production deploy:
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/yaml.sh
source "$LIB/yaml.sh"

dry_run="${DRY_RUN:-}"

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

# A chart's `version` is its own. `appVersion` names the upstream release, and is stamped only where it already tracks the chart's version.
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

# The lockfile records every workspace member's version, so stamping a manifest without refreshing it fails the drift check on the release commit itself.
# `--lockfile-only`: the release stamps versions and does not resolve dependencies.
if [[ "$stamped_pkg" == true ]]; then
  bun install --lockfile-only >/dev/null
  detail "refreshed bun.lock"
fi

# The template's release stamp lives in the tree, not the tag (ADR-0106): a forge copy is squashed with no history, and `project:init` reads this to write `_commit`.
echo "$version" >.template-version
detail "stamped .template-version"

# One top-level CHANGELOG.md, committed, so a reviewer sees what the release will
# say and it survives a shallow clone or a mirror.
step "rendering CHANGELOG.md"
cog changelog >CHANGELOG.md
ok "CHANGELOG.md written ($(wc -l <CHANGELOG.md) lines)"

if [[ -n "$dry_run" ]]; then
  warn "DRY_RUN set — not committing, tagging, or pushing"
  detail "would commit: chore(release): ${version}"
  detail "would tag:    ${version}"
  detail "the stamped fields, bun.lock and CHANGELOG.md are left in the working tree to inspect;"
  # .template-version needs both verbs: it is untracked before the first release and tracked after, and neither verb handles both states.
  detail "  git checkout infra/helm apps/*/package.json bun.lock CHANGELOG.md   discards them"
  detail "  git checkout .template-version 2>/dev/null || rm -f .template-version"
  exit 0
fi

git add -A
git commit -m "chore(release): ${version}"
git tag -a "$version" -m "$version"
git push origin HEAD "refs/tags/${version}"
ok "released ${version}"
