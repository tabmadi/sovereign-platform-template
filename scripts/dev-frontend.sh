#!/usr/bin/env bash
# The host-run `next dev` that the local edge routes `/` to, per ADR-0400 and ADR-0205.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

CLUSTER="${CLUSTER:-platform}"
# shellcheck source=lib/cluster.sh
source "$LIB/cluster.sh"
NS="platform"

CA_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/platform-local"
CA_FILE="${CA_DIR}/local-ca.crt"

k() { kubectl --context "$(cluster_ctx)" "$@"; }

# Extract it again on every run. A cluster:down creates a new CA, and an old file fails verification in a way that looks like a code problem.
if k -n "$NS" get secret local-ca-tls >/dev/null 2>&1; then
  mkdir -p "$CA_DIR"
  k -n "$NS" get secret local-ca-tls -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CA_FILE"
  export NODE_EXTRA_CA_CERTS="$CA_FILE"
  detail "trusting the local CA from ${CA_FILE}"
else
  warn "local-ca-tls not found. Check that cluster:up is running. TLS calls to the edge will fail"
fi

# Run through the island's own mise config, apps/frontend/.mise.toml, so the pinned node is on PATH, per ADR-0100.
# The `next` CLI and Turbopack's workers are `#!/usr/bin/env node` binaries, and bun starts node for them.
cd apps/frontend
exec mise run dev
