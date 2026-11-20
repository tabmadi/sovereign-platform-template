#!/usr/bin/env bash
# The appVersion of each chart names the release that the chart deploys, per ADR-0111.
# Renovate moves an image tag or a dependency, and nothing moves appVersion, so this check catches the drift.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking that each chart's appVersion matches what it deploys"

# The annotation `app-version-from` names the source of the version, in one of the forms that ADR-0111 lists.
source_version() {
  local dir="$1" from="$2" kind rest file expr name version archive
  kind="${from%%:*}"
  rest="${from#*:}"
  case "$kind" in
  dependency)
    version="$(NAME="$rest" yq '.dependencies[] | select(.name == strenv(NAME)) | .version' "${dir}/Chart.yaml")"
    archive="${dir}/charts/${rest}-${version}.tgz"
    [ -n "$version" ] && [ -f "$archive" ] || return 1
    tar -xzOf "$archive" "${rest}/Chart.yaml" | yq '.appVersion // ""'
    ;;
  yaml)
    file="${rest%%:*}"
    expr="${rest#*:}"
    [ -f "$file" ] || return 1
    yq "${expr} // \"\"" "$file"
    ;;
  arg)
    file="${rest%%:*}"
    name="${rest#*:}"
    [ -f "$file" ] || return 1
    sed -nE "s/^ARG ${name}=\"?([^\" ]+)\"?.*/\1/p" "$file" | head -1
    ;;
  *) return 1 ;;
  esac
}

offenders=""
checked=0
shopt -s nullglob globstar
for chart in infra/helm/**/Chart.yaml; do
  dir="$(dirname "$chart")"
  # A vendored subchart is upstream's, and its own wrapper chart is checked instead.
  case "$dir" in */charts/*) continue ;; esac
  from="$(yq '.annotations."app-version-from" // ""' "$chart")"
  app="$(yq '.appVersion // ""' "$chart")"
  if [ -z "$from" ]; then
    offenders="${offenders}  ${chart}: no app-version-from annotation"$'\n'
    continue
  fi
  [ "$from" = "none" ] && continue
  if ! want="$(source_version "$dir" "$from")" || [ -z "$want" ]; then
    offenders="${offenders}  ${chart}: no version found at ${from}"$'\n'
    continue
  fi
  checked=$((checked + 1))
  # Upstreams differ on a leading v, so v1.2.3 and 1.2.3 name the same release.
  if [ "${app#v}" != "${want#v}" ]; then
    offenders="${offenders}  ${chart}: appVersion ${app:-is empty}, but ${from} is ${want}"$'\n'
  fi
done

if [ -n "$offenders" ]; then
  warn "charts whose appVersion does not match what they deploy:"
  printf '%s' "$offenders" >&2
  detail "Set appVersion to the version of the source, or set app-version-from to none for a chart with no upstream." >&2
  fail "each appVersion must name the release that its chart deploys"
fi

ok "${checked} chart(s) name the release they deploy"
