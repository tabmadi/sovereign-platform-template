#!/usr/bin/env bash
# Conventional Commit gate over a commit range, per ADR-0103. A rebase or cherry-pick can bring a bad message past the commit-msg hook there.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

base="${BASE_REF:-master}"
base="${base#refs/heads/}"

# Prefer the remote-tracking ref. In CI the base branch is fetched but not checked out, so `master` alone can fail to resolve.
for candidate in "origin/${base}" "$base"; do
  if git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null; then
    ref="$candidate"
    break
  fi
done

if [[ -z "${ref:-}" ]]; then
  warn "no such base ref: ${base}. Skipping the commit-range check"
  exit 0
fi

range="${ref}..HEAD"
count="$(git rev-list --count "$range")"
if [[ "$count" -eq 0 ]]; then
  ok "no commits ahead of ${ref}"
  exit 0
fi

step "checking ${count} commit message(s) in ${range}"
cog check --ignore-merge-commits "$range"
ok "commit messages conform to Conventional Commits"
