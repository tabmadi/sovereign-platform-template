#!/usr/bin/env bash
# Fail when a project created from this template still wears the template's identity (ADR-0106, ADR-0003).

set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# A project that went through Copier has an identity on the record. This is also the escape hatch for a repository deliberately named differently from its module.
if [ -f .copier-answers.yml ]; then
  ok "identity recorded in .copier-answers.yml"
  exit 0
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
  # No remote: a tree that has not been attached to a forge yet, which includes the
  # output of `copier copy` before its first commit. Nothing distinguishes a copy
  # from the template here, so this gate reports rather than guesses.
  ok "no origin remote — identity not checked"
  exit 0
fi

# Both forms a forge serves, reduced to the repository name:
#   git@host:owner/repo.git   https://host/owner/repo.git
repo_name="$(basename -s .git "$origin_url")"

# The module path's last segment, less a major-version suffix — `…/acmeplat/v2` is
# still the `acmeplat` repository.
module_path="$(awk '/^module /{print $2; exit}' go.mod)"
module_name="$(basename "$module_path")"
[[ "$module_name" =~ ^v[0-9]+$ ]] && module_name="$(basename "$(dirname "$module_path")")"

if [ "$module_name" = "$repo_name" ]; then
  ok "module path matches the repository name (${repo_name})"
  exit 0
fi

# Report the whole job rather than the first symptom: the module path fails a build, the registry namespace publishes to someone else's images, and the apex points at a host the project does not own.
step "counting what still carries the template's identity"
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache --binary-files=without-match)
module_hits="$(grep -rlF "${PRUNE[@]}" -- "$module_path" . 2>/dev/null | wc -l)"
apex_hits="$(grep -rlF "${PRUNE[@]}" -- "example.com" . 2>/dev/null | wc -l)"
detail "module path ${module_path} — ${module_hits} files"
detail "apex host example.com — ${apex_hits} files"

echo
fail "this project still carries the template's identity — the repository is '${repo_name}', the module path says '${module_name}'

A forge-side 'Use this template' copies the tree and runs nothing. Adopt the
identity before the first push, then commit the result (ADR-0106):

    bash scripts/project-rename.sh <slug> <module-path> <apex-host> <image-registry>
    mise run gen

Contributing to the template rather than adopting it? Keep the repository name and
this gate stays quiet."
