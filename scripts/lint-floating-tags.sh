#!/usr/bin/env bash
# Fail on floating container image and tool tags, per ADR-0101.
# It reads Dockerfiles, Helm values, GitHub workflows, and .mise.toml.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

FOUND=0

scan() {
  local label="$1"
  shift
  local pattern="$1"
  shift
  local hits
  # image-refs.txt is generated from the charts, where a floating tag is an upstream chart's choice. This gate covers the values a human writes.
  # The path list is split into separate grep arguments on purpose.
  # shellcheck disable=SC2068
  hits=$(grep -RInE --exclude-dir=node_modules --exclude=image-refs.txt "$pattern" $@ 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    warn "${label}:"
    echo "$hits" | sed 's/^/    /' >&2
    FOUND=1
  fi
}

# infra/local is in the list because nobody reviews a dev stand-in. A version that changed for one engineer and not another is a bug neither can reproduce.
# The Temporal stand-in stayed on `latest` for as long as this gate did not check it.
paths=(Dockerfile infra/helm infra/local .github/workflows .mise.toml services apps)

# Floating image tags in Helm values, Dockerfiles, and workflows.
scan "floating image tags" \
  '(:latest|:stable|:main)([^A-Za-z0-9_.-]|$)' \
  "${paths[@]}"

# Unpinned action versions in workflows: `uses: foo/bar@main`, `@master`, or `@vN` without a SHA.
scan "unpinned GitHub Action references" \
  'uses: [^ ]+@(main|master|develop)\b' \
  .github/workflows 2>/dev/null || true

if [[ "$FOUND" -ne 0 ]]; then
  fail "floating tags are forbidden by ADR-0101. Pin to a concrete version or SHA"
fi

ok "no floating tags"
