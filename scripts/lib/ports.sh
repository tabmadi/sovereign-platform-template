# shellcheck shell=bash

if [[ -n "${__PORTS_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__PORTS_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# service:port — the registry itself.
__LOCAL_PORTS="
analytics:8086
authz:8085
catalog:8081
orders:8082
orgs:8083
payment:8084
"

# service_port <svc> — prints the registered local port, or fails.
service_port() {
  local svc="${1:?service_port: missing service}" line
  line="$(printf '%s\n' "$__LOCAL_PORTS" | grep "^${svc}:" || true)"
  # warn and return, never fail: lint:ports and lint:service-contract call this
  # as a probe in a condition, where an exit would abort the gate mid-run.
  if [ -z "$line" ]; then
    warn "no local port registered for ${svc} — add it to scripts/lib/ports.sh"
    return 1
  fi
  printf '%s' "${line#*:}"
}

# all_port_entries — prints every "service:port" line. Used by lint:ports.
all_port_entries() { printf '%s\n' "$__LOCAL_PORTS" | grep ':'; }
