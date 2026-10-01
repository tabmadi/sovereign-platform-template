# shellcheck shell=bash

if [[ -n "${__PORTS_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__PORTS_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# service:port. This is the registry.
__LOCAL_PORTS="
analytics:8086
authz:8085
catalog:8081
orders:8082
orgs:8083
payment:8084
"

# service_port <svc> prints the registered local port, or fails.
service_port() {
  local svc="${1:?service_port: missing service}" line
  line="$(printf '%s\n' "$__LOCAL_PORTS" | grep "^${svc}:" || true)"
  # Warn and return, never fail. lint:ports and lint:service-contract call this in a condition, and an exit stops the gate.
  if [ -z "$line" ]; then
    warn "no local port registered for ${svc}. Add it to scripts/lib/ports.sh"
    return 1
  fi
  printf '%s' "${line#*:}"
}

# all_port_entries prints every `service:port` line, for lint:ports.
all_port_entries() { printf '%s\n' "$__LOCAL_PORTS" | grep ':'; }
