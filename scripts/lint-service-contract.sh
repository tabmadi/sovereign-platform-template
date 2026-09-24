#!/usr/bin/env bash
# The service contract gate (ADR-0205): every service provides the same artifacts, because the platform discovers services through them rather than through a registry.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"
# shellcheck source=lib/ports.sh
source "$LIB/ports.sh"

rc=0
checked=0

# Environments are the values directories that exist. Adding one makes it required
# for every service on the next run, which is the intent.
envs=()
for d in infra/gitops/services/*/; do envs+=("$(basename "$d")"); done

# A service may opt out of an environment ON PURPOSE, but it has to say so, in the
# file the opt-out affects. Silence is the failure mode this check exists to remove.
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

  # `server` only for a service that has one; a worker-only deployable declares `worker` (ADR-0101).
  # `generate` and `migrate` are required of a service that has the input, and of no service that has neither.
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

  # Both SLIs are computed from a request's RED histogram, so the file is owed by a service that answers requests (ADR-0500).
  if [ -d "services/${svc}/cmd/server" ] && [ ! -f "${dir}slo.yaml" ]; then
    warn "${svc}: no slo.yaml — ADR-0500 requires an availability and a latency SLI per service. Copy services/_template/slo.yaml"
    rc=1
  fi

  # depguard's unit is a file pattern with a deny list, so the relational constraint takes one rule per service (ADR-0101).
  # A new service that adds no block breaks no rule, which is the silence this check removes.
  grep -q "service-isolation-${svc}:" .golangci.yml || {
    warn "${svc}: no 'service-isolation-${svc}' depguard rule in .golangci.yml — nothing stops a sibling importing it"
    rc=1
  }

  # Only for a service that binds a port; uniqueness and the reverse direction are lint:ports' job.
  if [ -d "services/${svc}/cmd/server" ]; then
    service_port "$svc" >/dev/null 2>&1 || {
      warn "${svc}: no local port in scripts/lib/ports.sh"
      rc=1
    }
  fi

  for env in "${envs[@]}"; do
    if [ -f "infra/gitops/services/${env}/values/${svc}.yaml" ]; then continue; fi
    if opted_out "$svc" "$env"; then
      detail "${svc}: not deployed to ${env} (declared)"
      continue
    fi
    warn "${svc}: no infra/gitops/services/${env}/values/${svc}.yaml — the ApplicationSet will not deploy it to ${env}, silently. Add the file, or declare '# platform/not-deployed: ${env}' in services/${svc}/.mise.toml"
    rc=1
  done
done

[ "$rc" -eq 0 ] && ok "service contract satisfied (${checked} services)"
exit "$rc"
