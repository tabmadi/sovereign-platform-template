#!/usr/bin/env bash
# Commit the values files that a promotion rewrote, and push them to the default branch that Argo CD reconciles from, per ADR-0201.
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

# A push between this job's checkout and its push moves the branch. The rewrite changes only image pins.
# So it rebases cleanly onto anything except another promotion of the same file.
for attempt in 1 2 3; do
  if git push -q origin "HEAD:${branch}"; then
    ok "promotion pushed to ${branch}"
    exit 0
  fi
  warn "push rejected on attempt ${attempt}. Rebasing onto ${branch}"
  git pull -q --rebase origin "$branch"
done
fail "could not push the promotion to ${branch}"
