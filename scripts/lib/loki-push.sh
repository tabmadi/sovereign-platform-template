#!/usr/bin/env bash
# Push one structured line to Loki from outside the cluster (ADR-0104, ADR-0500).

# loki_push <stream-labels-json> <line-json>
loki_push() {
  local labels="$1" line="$2"

  if [ -z "${LOKI_PUSH_URL:-}" ]; then
    warn "LOKI_PUSH_URL unset — supply-chain record not filed (this build is still signed and attested)"
    return 0
  fi

  # Nanoseconds since the epoch, as a string: Loki's push API takes the timestamp as
  # a decimal string and rejects a JSON number for it.
  local ns
  ns="$(date +%s%N)"

  local payload
  payload="$(jq -cn --argjson stream "$labels" --arg ns "$ns" --arg line "$line" \
    '{streams: [{stream: $stream, values: [[$ns, $line]]}]}')"

  # call is still tolerated by the caller, but a broken push should say so.
  if curl --silent --show-error --fail --max-time 20 \
    -H "Content-Type: application/json" \
    ${LOKI_PUSH_TENANT:+-H "X-Scope-OrgID: ${LOKI_PUSH_TENANT}"} \
    ${LOKI_PUSH_AUTH:+-H "Authorization: ${LOKI_PUSH_AUTH}"} \
    -X POST "${LOKI_PUSH_URL%/}/loki/api/v1/push" \
    --data-binary "$payload" >/dev/null; then
    detail "supply-chain record filed to Loki"
  else
    warn "supply-chain record could NOT be filed to Loki (the build itself is unaffected)"
  fi
}
