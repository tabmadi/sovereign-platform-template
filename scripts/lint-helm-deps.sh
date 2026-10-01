#!/usr/bin/env bash
# Helm dependency resolution must not depend on the caller's machine, per ADR-0101.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking helm dependency calls resolve without pre-registered repos"

# A line that calls `dependency build` is fine only if it also names `dependency update`, on the same line or on the next as a `||` fallback.
offenders=""
while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  content="${rest#*:}"
  # A comment is not a call: the pattern looks like prose as much as like code. This file excludes itself for the same reason.
  case "${content#"${content%%[![:space:]]*}"}" in
  "#"*) continue ;;
  esac
  # The call and the line after it, which holds a `|| update` fallback.
  window="$(sed -n "${line},$((line + 1))p" "$file")"
  case "$window" in
  *"dependency update"*) ;;
  *) offenders="${offenders}  ${file}:${line}"$'\n' ;;
  esac
  # This file is excluded because it names what it forbids, in the pattern and in the reason for the pattern.
done < <(grep -rn 'dependency build' --include='*.sh' --exclude="$(basename "${BASH_SOURCE[0]}")" scripts/ || true)

if [ -n "$offenders" ]; then
  warn "\`helm dependency build\` with no \`update\` fallback:"
  printf '%s' "$offenders" >&2
  detail "build needs the repo already registered, and a clean runner has none." >&2
  detail "Use \`dependency update\`, or \`build <chart> || update <chart>\`." >&2
  fail "helm dependency calls must resolve from Chart.yaml alone"
fi

ok "helm dependency calls resolve from Chart.yaml alone"
