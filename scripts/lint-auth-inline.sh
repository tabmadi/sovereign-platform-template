#!/usr/bin/env bash
# Auth single-source lint: authentication is defined in exactly one place, and the real stack enforces it, per ADR-0305.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

VALUES="infra/helm/platform/ory/values.yaml"
# `rc`, not `fail`: the accumulator must not shadow the log.sh verb, which the verdict below calls after every check.
rc=0

# Markers that appear only when kratos or oathkeeper config or the string artefacts are inline in the chart values.
# The correct file has only the `enabled` flags and the deferred Hydra block.
PATTERNS='accessRules|identitySchemas|default_schema_id|authenticators:|access_rules:|selfservice:|cookie_session|ory_kratos_session'
# Match with original line numbers, then drop comment lines, because the header doc pointers name these keys.
# A comment is `<n>:<spaces>#` followed by text.
if hits=$(grep -nEi "$PATTERNS" "$VALUES" 2>/dev/null | grep -vE '^[0-9]+:\s*#'); then
  warn "auth config is inline in ${VALUES}. It must live only in infra/auth/*:"
  echo "$hits" >&2
  rc=1
fi

# The canonical artefacts must exist, because the injection points reference them.
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

# The scope is the whole application, per ADR-0600: a bypass goes in a server action or a layout, where it looks like a convenience.
# Comments are dropped, so this file's prose and the app's ADR pointers do not match.
AUTH_PATHS=(apps/frontend/src)
# An environment-conditional branch is a finding only when it conditions the session.
# proxy.ts relaxes the CSP for `next dev`, which grants nothing. So NODE_ENV counts only with an auth word on the same line.
BYPASS='DEV_AUTH|AUTH_BYPASS|BYPASS_AUTH|dev-?auth|auth-?bypass|fake[-_ ]?session|NODE_ENV.*(session|auth|identity|bypass)|(session|auth|identity|bypass).*NODE_ENV'
for p in "${AUTH_PATHS[@]}"; do
  [ -e "$p" ] || continue
  if hits=$(grep -rniE "$BYPASS" "$p" | grep -vE '^[^:]+:[0-9]+:\s*(//|\*|/\*)'); then
    warn "development-only auth code in ${p}. The frontend has one auth path, and it is the production path, per ADR-0600:"
    echo "$hits" >&2
    detail "To develop against mocked data while logged in, use: mise run cluster:up" >&2
    rc=1
  fi
done

[ "$rc" -eq 0 ] || fail "auth single-source: inline config or dev-only auth code above"
ok "auth single-source: no inline config in ${VALUES}, no dev-only auth code in the frontend"
