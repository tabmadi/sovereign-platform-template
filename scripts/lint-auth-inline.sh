#!/usr/bin/env bash
# Auth single-source lint: authentication is defined in exactly one place and enforced by the real stack (ADR-0305).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

VALUES="infra/helm/platform/ory/values.yaml"
# `rc`, not `fail`: the accumulator must not shadow log.sh's verb, which the
# verdict below calls once every check has run.
rc=0

# Markers that only appear when kratos/oathkeeper config or the string artefacts
# have been inlined into the chart values. The legitimate file carries only the
# `enabled` flags and the (deferred) Hydra block.
PATTERNS='accessRules|identitySchemas|default_schema_id|authenticators:|access_rules:|selfservice:|cookie_session|ory_kratos_session'
# Match with original line numbers, then drop comment lines (the header doc-pointers
# legitimately name these keys) — a comment is `<n>:<spaces>#…`.
if hits=$(grep -nEi "$PATTERNS" "$VALUES" 2>/dev/null | grep -vE '^[0-9]+:\s*#'); then
  warn "auth config re-inlined into ${VALUES} — it must live only in infra/auth/*:"
  echo "$hits" >&2
  rc=1
fi

# The canonical artefacts must exist (the injection points reference them).
for f in \
  infra/auth/kratos/values.yaml \
  infra/auth/oathkeeper/values.yaml \
  infra/auth/oathkeeper/access-rules.json \
  infra/auth/kratos/identity-schemas/user.v1.json; do
  if [ ! -f "$f" ]; then
    warn "missing canonical auth artefact: ${f}"
    rc=1
  fi
done

# Scope is the whole application (ADR-0600): a bypass goes in a server action or a layout, where it reads like a convenience.
# Comments are dropped so this file's prose and the app's ADR pointers do not trip it.
AUTH_PATHS=(apps/frontend/src)
# An environment-conditional branch is only a finding when it is conditioning the
# SESSION — proxy.ts legitimately relaxes the CSP for `next dev`, which grants
# nothing. So NODE_ENV counts only alongside an auth word on the same line.
BYPASS='DEV_AUTH|AUTH_BYPASS|BYPASS_AUTH|dev-?auth|auth-?bypass|fake[-_ ]?session|NODE_ENV.*(session|auth|identity|bypass)|(session|auth|identity|bypass).*NODE_ENV'
for p in "${AUTH_PATHS[@]}"; do
  [ -e "$p" ] || continue
  if hits=$(grep -rniE "$BYPASS" "$p" | grep -vE '^[^:]+:[0-9]+:\s*(//|\*|/\*)'); then
    warn "development-only auth code in ${p} — the frontend has ONE auth path and it is the production one (ADR-0600):"
    echo "$hits" >&2
    detail "To develop against mocked data while logged in, use: mise run cluster:up" >&2
    rc=1
  fi
done

[ "$rc" -eq 0 ] || fail "auth single-source: inline config or dev-only auth code above"
ok "auth single-source: no inline config in ${VALUES}, no dev-only auth code in the frontend"
