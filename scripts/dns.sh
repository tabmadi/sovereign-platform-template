#!/usr/bin/env bash
# Reconcile the provider's zones with infra/dns/dnsconfig.js, per ADR-0206. `check` reports the difference and changes nothing.
# `apply` makes the provider match, and it deletes the records that the file does not declare.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CONFIG="infra/dns/dnsconfig.js"
CREDS="infra/dns/creds.json"
SECRET="infra/dns/secrets.enc.yaml"

usage() { fail "usage: dns.sh <check|apply>"; }
[ "$#" -eq 1 ] || usage

# The template ships no provider, because a project chooses its own. The placeholder is not a provider that dnscontrol can run.
[ "$(jq -r '.zone.TYPE' "$CREDS")" != "NONE" ] ||
  fail "${CREDS} names no provider yet. Replace its 'zone' entry. See infra/dns/README.md"

# creds.json names environment variables, and the secret file holds their values. A project with no provider yet has no such file.
if [ -f "$SECRET" ]; then
  exports="$(sops --decrypt "$SECRET" |
    yq -r '.stringData | to_entries | .[] | "export " + .key + "=" + (.value | @sh)')" ||
    fail "cannot decrypt ${SECRET}. Your age key is not a recipient of it"
  eval "$exports"
fi

case "$1" in
check)
  step "comparing ${CONFIG} with the provider"
  # `preview` exits 0 with pending changes. This flag makes a difference a failure.
  if dnscontrol preview --expect-no-changes --config "$CONFIG" --creds "$CREDS"; then
    ok "the provider matches ${CONFIG}"
  else
    fail "the provider differs from ${CONFIG}. Run 'mise run dns:apply'"
  fi
  ;;
apply)
  warn "apply deletes provider records that ${CONFIG} does not declare"
  step "reconciling the provider with ${CONFIG}"
  dnscontrol push --config "$CONFIG" --creds "$CREDS"
  ok "the provider matches ${CONFIG}"
  ;;
*) usage ;;
esac
