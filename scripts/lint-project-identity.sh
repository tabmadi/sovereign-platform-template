#!/usr/bin/env bash
# Fail when a project still has the identity of the copy it started from, per ADR-0117 and ADR-0003.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# The gate names the footprints, template/ holds the scope that `just init` removes, and a `*.local.md` file holds one engineer's untracked notes.
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=.rumdl_cache --exclude-dir=template --exclude='*.local.md'
  --exclude=lint-project-identity.sh --binary-files=without-match)

# The template's footprints. `project-rename.sh` rewrites this set before the first push.
FOOTPRINTS=(
  "github.com/tabmadi/sovereign-platform-template"
  "ghcr.io/tabmadi/sovereign-platform-template"
  "example.com"
  "example-dev-cp"
  "example-staging-cp"
  "example-prod-cp"
)

# `just init` removes scripts/project-init.sh. A copy that still has it has not adopted an identity yet,
# and the origin remote decides below whether that is the template itself.
if [ ! -f scripts/project-init.sh ]; then
  slug="$(awk '$1 == "slug:" {print $2; exit}' infra/project.yaml 2>/dev/null)"
  [ -n "$slug" ] || fail "infra/project.yaml carries no slug"

  problems=()
  grep -rqF -- "${slug}-" infra/talos/inventory 2>/dev/null ||
    problems+=("no Talos node is named '${slug}-<role>'. The inventory still has the names of the copy")
  for footprint in "${FOOTPRINTS[@]}"; do
    hits="$({ grep -rlF "${PRUNE[@]}" -- "$footprint" . 2>/dev/null || true; } | wc -l)"
    [ "$hits" -eq 0 ] || problems+=("${hits} file(s) still carry '${footprint}'")
  done

  if [ "${#problems[@]}" -gt 0 ]; then
    warn "this project still has the identity of the copy it started from:"
    printf '  · %s\n' "${problems[@]}" >&2
    fail "rename the rest by hand, then run 'just gen'"
  fi
  ok "identity applied: ${slug}"
  exit 0
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
  # No remote: a tree that is not attached to a forge yet, such as a copy from `nix flake new` before its first push.
  # Here a copy looks the same as the template, so this gate reports and does not guess.
  ok "no origin remote, identity not checked"
  exit 0
fi

# The two forms that a forge serves, reduced to the repository name:
#   git@host:owner/repo.git   https://host/owner/repo.git
repo_name="$(basename -s .git "$origin_url")"

# The module path's last segment, without a major-version suffix: `github.com/acme/acmeplat/v2` is still the `acmeplat` repository.
module_path="$(awk '/^module /{print $2; exit}' go.mod)"
module_name="$(basename "$module_path")"
[[ "$module_name" =~ ^v[0-9]+$ ]] && module_name="$(basename "$(dirname "$module_path")")"

if [ "$module_name" = "$repo_name" ]; then
  ok "module path matches the repository name ${repo_name}"
  exit 0
fi

# Report the whole job, not the first symptom. The module path fails a build, and the registry namespace publishes to another owner's images.
# The apex points at a host the project does not own.
step "counting what still carries the template's identity"
module_hits="$({ grep -rlF "${PRUNE[@]}" -- "$module_path" . 2>/dev/null || true; } | wc -l)"
apex_hits="$({ grep -rlF "${PRUNE[@]}" -- "example.com" . 2>/dev/null || true; } | wc -l)"
detail "module path ${module_path}: ${module_hits} files"
detail "apex host example.com: ${apex_hits} files"

echo
fail "this project still has the template's identity. The repository is '${repo_name}', and the module path says '${module_name}'

A copy from the template button runs nothing. Adopt an identity before the
first push, then commit the result, per ADR-0117:

    just init
    just gen

To contribute to the template and not adopt it, keep the repository name, and
this gate stays quiet."
