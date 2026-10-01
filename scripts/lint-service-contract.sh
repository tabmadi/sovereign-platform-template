#!/usr/bin/env bash
# The service contract gate, per ADR-0205: every service provides the same artifacts.
# The platform finds services through these artifacts, not through a registry.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/ports.sh
source "$LIB/ports.sh"

rc=0
checked=0

# Environments are the values directories that exist. A new one is required for every service on the next run, as intended.
envs=()
for d in infra/gitops/services/*/; do envs+=("$(basename "$d")"); done

# A service can opt out of an environment on purpose, but it must say so in the file that the opt-out affects. This check exists to remove silent gaps.
opted_out() { grep -qs "platform/not-deployed: *${2}" "services/${1}/.mise.toml"; }

for dir in services/*/; do
  svc="$(basename "$dir")"
  [ "${svc#_}" = "$svc" ] || continue # _template is the source, not a service
  checked=$((checked + 1))

  for f in .mise.toml .env.example Dockerfile README.md; do
    [ -f "${dir}${f}" ] || {
      warn "${svc}: missing ${f}"
      rc=1
    }
  done

  # `server` only for a service that has one. A worker-only deployable declares `worker`, per ADR-0101.
  # `generate` and `migrate` are required of a service that has the input, and of no other service.
  tasks="test lint build"
  if [ -d "services/${svc}/cmd/server" ]; then
    tasks="server ${tasks}"
  else
    tasks="worker ${tasks}"
  fi
  if [ -f "${dir}openapi.yaml" ] || [ -d "${dir}queries" ]; then
    tasks="generate ${tasks}"
  fi
  if [ -d "${dir}migrations" ]; then
    tasks="migrate ${tasks}"
  fi
  for t in ${tasks}; do
    grep -q "^\[tasks\.${t}\]" "${dir}.mise.toml" 2>/dev/null || {
      warn "${svc}: .mise.toml declares no [tasks.${t}]"
      rc=1
    }
  done

  # Both SLIs come from a request's RED histogram, so a service that answers requests owes the file, per ADR-0500.
  if [ -d "services/${svc}/cmd/server" ] && [ ! -f "${dir}slo.yaml" ]; then
    warn "${svc}: no slo.yaml. ADR-0500 requires an availability SLI and a latency SLI for each service. Copy services/_template/slo.yaml"
    rc=1
  fi

  # A depguard rule is a file pattern with a deny list, so the constraint between services needs one rule for each service, per ADR-0101.
  # A new service with no block breaks no rule, and this check closes that gap.
  grep -q "service-isolation-${svc}:" .golangci.yml || {
    warn "${svc}: no 'service-isolation-${svc}' depguard rule in .golangci.yml. Nothing stops another service from importing it"
    rc=1
  }

  # Only for a service that binds a port. lint:ports checks uniqueness and the reverse direction.
  if [ -d "services/${svc}/cmd/server" ]; then
    service_port "$svc" >/dev/null 2>&1 || {
      warn "${svc}: no local port in scripts/lib/ports.sh"
      rc=1
    }
  fi

  for env in "${envs[@]}"; do
    if [ -f "infra/gitops/services/${env}/values/${svc}.yaml" ]; then continue; fi
    if opted_out "$svc" "$env"; then
      detail "${svc}: not deployed to ${env}, as declared"
      continue
    fi
    warn "${svc}: no infra/gitops/services/${env}/values/${svc}.yaml. The ApplicationSet does not deploy it to ${env}, and nothing reports it. Add the file, or declare '# platform/not-deployed: ${env}' in services/${svc}/.mise.toml"
    rc=1
  done
done

[ "$rc" -eq 0 ] && ok "service contract satisfied for ${checked} services"
exit "$rc"
