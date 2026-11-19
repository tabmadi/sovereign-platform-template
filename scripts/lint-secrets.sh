#!/usr/bin/env bash
# No committed file holds a plaintext secret, per ADR-0202. It extends the shared gitleaks rule set and does not replace it.
# The working tree scan reads the files that git tracks or would track, the same set as the check in the sandbox.
# A file that git ignores, such as .env, holds local secrets on purpose and is never committed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

args=(--config "$ROOT/.config/gitleaks.toml" --gitleaks-ignore-path "$ROOT/.gitleaksignore" --redact --no-banner)

if [[ -n "${GITLEAKS_HISTORY:-}" ]]; then
  step "scanning full git history for plaintext secrets"
  gitleaks git "${args[@]}"
else
  step "scanning the tracked files for plaintext secrets"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  git ls-files -z --cached --others --exclude-standard | xargs -0 -r ls -d 2>/dev/null | tr '\n' '\0' |
    tar --null -T - -cf - | tar -x -C "$work"
  (cd "$work" && gitleaks dir . "${args[@]}")
fi

ok "no plaintext secrets found"
