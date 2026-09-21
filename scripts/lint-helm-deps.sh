#!/usr/bin/env bash
# Helm dependency resolution must not depend on the caller's machine (ADR-0101).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

step "checking helm dependency calls resolve without pre-registered repos"

# A line calling `dependency build` is fine only if it also names `dependency
# update` — on the same line, or on the next one as a `||` fallback.
offenders=""
while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  content="${rest#*:}"
  # A comment is not a call: the pattern reads as prose as readily as it reads as code. This file already excludes itself for the same reason.
  case "${content#"${content%%[![:space:]]*}"}" in
  "#"*) continue ;;
  esac
  # The call plus the line after it, which is where a `|| … update` fallback lives.
  window="$(sed -n "${line},$((line + 1))p" "$file")"
  case "$window" in
  *"dependency update"*) ;;
  *) offenders="${offenders}  ${file}:${line}"$'\n' ;;
  esac
  # This file is excluded because it necessarily names the thing it forbids — in
  # the pattern and in the explanation of why the pattern exists.
done < <(grep -rn 'dependency build' --include='*.sh' --exclude="$(basename "${BASH_SOURCE[0]}")" scripts/ || true)

if [ -n "$offenders" ]; then
  warn "\`helm dependency build\` with no \`update\` fallback:"
  printf '%s' "$offenders" >&2
  detail "build needs the repo already registered; a clean runner has none." >&2
  detail "Use \`dependency update\`, or \`build … || update …\`." >&2
  fail "helm dependency calls must resolve from Chart.yaml alone"
fi

ok "helm dependency calls resolve from Chart.yaml alone"
