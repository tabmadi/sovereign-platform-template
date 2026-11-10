#!/usr/bin/env bash
# The git identity of a commit that CI makes, per ADR-0201. It is never the actor who pushed: CI wrote the commit, not that person.
# GitHub shows its own bot for the github-actions address. Another forge has no such account, so the commit names the `ci` machine user.
# That commit is signed with the key of `ci`, per ADR-0102.
ci_git_identity() {
  local host="${GITHUB_SERVER_URL:-https://github.com}"
  host="${host#*://}"
  if [ "$host" = github.com ]; then
    git config user.name "github-actions[bot]"
    git config user.email "41898283+github-actions[bot]@users.noreply.github.com"
  else
    git config user.name ci
    git config user.email "ci@noreply.${host}"
    ci_git_signing
  fi
}

# The key is a SOPS secret that only CI opens. Without SOPS_AGE_KEY the commit stays unsigned, and the forge refuses its push.
ci_git_signing() {
  local file="infra/ci/commit-signing-key.enc.yaml" plain
  if [ -z "${SOPS_AGE_KEY:-}" ] || [ ! -f "$file" ]; then
    warn "no commit-signing key. The promotion commit is unsigned"
    return 0
  fi
  GNUPGHOME="$(mktemp -d)"
  chmod 700 "$GNUPGHOME"
  export GNUPGHOME
  plain="$(sops -d "$file")"
  yq -r '.stringData["private.asc"]' <<<"$plain" | gpg --batch --quiet --import
  git config user.signingkey "$(yq -r '.stringData.fingerprint' <<<"$plain")"
  git config commit.gpgsign true
}

# A rebase signs again, so the key stays until the script exits.
ci_git_forget_key() {
  if [ -n "${GNUPGHOME:-}" ]; then
    gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf "$GNUPGHOME"
  fi
}
