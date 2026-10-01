#!/usr/bin/env bash
# Scaffold a new service from services/_template/, per ADR-0101.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

NAME="${1:?usage: new-service.sh <service-name>}"
DEST="services/${NAME}"

if [[ -d "$DEST" ]]; then
  fail "${DEST} already exists"
fi

cp -r services/_template "$DEST"

# Strip the //go:build _template constraint from every Go file.
find "$DEST" -name "*.go" -print0 | while IFS= read -r -d '' f; do
  # Remove the build constraint line and the blank line that follows it.
  sed -i '/^\/\/go:build _template$/{N;d;}' "$f"
done

# Put the service name in the obvious places.
find "$DEST" -type f \( -name "*.go" -o -name "*.yaml" -o -name "*.md" -o -name "Dockerfile" -o -name "*.toml" \) \
  -exec sed -i "s/_template/${NAME}/g" {} +

# Stamp the init migration with the current timestamp.
ts=$(date -u +%Y%m%d%H%M%S)
mv "${DEST}/migrations/"*_init.sql "${DEST}/migrations/${ts}_init.sql"

ok "created ${DEST}. Next:"
detail "  1. Register a local port in scripts/lib/ports.sh, and set the same PORT in"
detail "     ${DEST}/.mise.toml. It ships 80XX and fails lint until you do"
detail "  2. Edit ${DEST}/openapi.yaml to define your routes"
detail "  3. mise run gen"
detail "  4. Implement handlers/ and wire them in cmd/server/main.go"
detail "  5. Keep only the dep:* tasks you read, and add svc:* for every service"
detail "     you call over HTTP. An undeclared callee fails at runtime, not at startup"
detail "  6. Add infra/gitops/services/<env>/values/${NAME}.yaml for every env."
detail "     The ApplicationSet generates one Argo app for each values file, so with a"
detail "     missing file the service is absent from that environment, with no error"
printf '\n'
detail "Then: mise run lint:service-contract   # checks all of the above, per ADR-0205"
