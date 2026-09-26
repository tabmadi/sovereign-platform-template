#!/usr/bin/env bash
# Commit the values files a promotion rewrote and push them to the default branch, where Argo CD reconciles from (ADR-0201).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

sha="${SHA:-}"
[[ -n "$sha" ]] || fail "SHA is unset"
branch="${BRANCH:-master}"

if git diff --quiet -- infra/gitops; then
  ok "no values file changed"
  exit 0
fi

git config user.name "${GITHUB_ACTOR:-ci}"
git config user.email "${GITHUB_ACTOR:-ci}@noreply.${GITHUB_SERVER_URL#*://}"
git add infra/gitops
git commit -q -m "chore(deploy): promote ${sha:0:12}"

# A push that lands between this job's checkout and its push moves the branch; the rewrite touches only image pins, so it rebases cleanly onto anything but another promotion of the same file.
for attempt in 1 2 3; do
  if git push -q origin "HEAD:${branch}"; then
    ok "promotion pushed to ${branch}"
    exit 0
  fi
  warn "push rejected (attempt ${attempt}) — rebasing onto ${branch}"
  git pull -q --rebase origin "$branch"
done
fail "could not push the promotion to ${branch}"
