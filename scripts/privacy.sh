#!/usr/bin/env bash
# Start a subject's erasure or export, per ADR-0301. It runs the Temporal CLI inside the cluster's admin-tools pod,
# so it needs a kubeconfig for the environment and nothing else. KUBE_CONTEXT picks the cluster, and the current
# context is the default.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

[ "$#" -eq 2 ] || fail "usage: privacy.sh <erase|export> <identity-id>"
action="$1" identity="$2"
[[ "$identity" =~ ^[0-9a-f-]{36}$ ]] || fail "not a Kratos identity id: ${identity}"

ctx=()
[ -z "${KUBE_CONTEXT:-}" ] || ctx=(--context "$KUBE_CONTEXT")
temporal() { kubectl "${ctx[@]}" -n platform exec deploy/temporal-admintools -- temporal "$@"; }
input="$(jq -cn --arg id "$identity" '{IdentityID: $id}')"

case "$action" in
erase)
  # The workflow id comes from the identity, so a second request for the same subject joins the first.
  temporal workflow start --type EraseSubject --task-queue platform-queue \
    --workflow-id "erase-subject-${identity}" --id-conflict-policy UseExisting --input "$input" >/dev/null
  ok "erasure started as erase-subject-${identity}. Follow it in the Temporal UI"
  ;;
export)
  # The export is the workflow's result. It goes to stdout, so it can be piped to a file.
  temporal workflow execute --type ExportSubject --task-queue platform-queue \
    --workflow-id "export-subject-${identity}-$(date +%s)" --input "$input" --output json |
    jq -r '.result | fromjson? // .'
  ;;
*) fail "usage: privacy.sh <erase|export> <identity-id>" ;;
esac
