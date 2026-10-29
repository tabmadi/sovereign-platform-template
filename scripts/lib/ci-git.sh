#!/usr/bin/env bash
# The git identity of a commit that CI makes, per ADR-0201. It is never the actor who pushed: CI wrote the commit, not that person.
# GitHub shows its own bot for the github-actions address. Another forge has no such account, so the commit names the `ci` machine user.
ci_git_identity() {
  local host="${GITHUB_SERVER_URL:-https://github.com}"
  host="${host#*://}"
  if [ "$host" = github.com ]; then
    git config user.name "github-actions[bot]"
    git config user.email "41898283+github-actions[bot]@users.noreply.github.com"
  else
    git config user.name ci
    git config user.email "ci@noreply.${host}"
  fi
}
