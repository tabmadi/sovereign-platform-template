#!/usr/bin/env bash
# Fail when a project created from this template still has the template's identity, per ADR-0106 and ADR-0003.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# The gate and its test name the footprints, the answers file names its template, and a `*.local.md` file holds one engineer's untracked notes.
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache --exclude=.copier-answers.yml --exclude='*.local.md'
  --exclude=lint-project-identity.sh --exclude=test-template.sh --binary-files=without-match)

# The template's footprints. `project-rename.sh` rewrites this set before the first push.
FOOTPRINTS=(
  "github.com/tabmadi/sovereign-platform-template"
  "ghcr.io/tabmadi/sovereign-platform-template"
  "example.com"
  "example-dev-cp"
  "example-staging-cp"
  "example-prod-cp"
)

# A generated project has a recorded identity. The file is present for the whole life of the project, so its presence proves nothing.
# So the gate checks that the recorded answers were applied and that no footprint is left.
if [ -f .copier-answers.yml ]; then
  module_path="$(yq -r '.module_path // ""' .copier-answers.yml)"
  project_slug="$(yq -r '.project_slug // ""' .copier-answers.yml)"
  [ -n "$module_path" ] || fail ".copier-answers.yml carries no module_path"
  [ -n "$project_slug" ] || fail ".copier-answers.yml carries no project_slug"

  problems=()
  actual="$(awk '/^module /{print $2; exit}' go.mod)"
  [ "$actual" = "$module_path" ] ||
    problems+=("go.mod says '${actual}', the answers say '${module_path}'")
  grep -rqF -- "${project_slug}-" infra/talos/inventory 2>/dev/null ||
    problems+=("no Talos node is named '${project_slug}-<role>'. The inventory still has the template's names")
  for footprint in "${FOOTPRINTS[@]}"; do
    # The brace group absorbs grep's exit 1 under `pipefail`, which would otherwise end the run.
    hits="$({ grep -rlF "${PRUNE[@]}" -- "$footprint" . 2>/dev/null || true; } | wc -l)"
    [ "$hits" -eq 0 ] || problems+=("${hits} file(s) still carry '${footprint}'")
  done

  if [ "${#problems[@]}" -gt 0 ]; then
    warn "this project still has the template's identity:"
    printf '  · %s\n' "${problems[@]}" >&2
    fail "adopt the identity with scripts/project-rename.sh, then run 'mise run gen'"
  fi
  ok "identity recorded and applied: ${project_slug}"
  exit 0
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
  # No remote: a tree that is not attached to a forge yet, including the output of `copier copy` before its first commit.
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

A forge-side 'Use this template' copies the tree and runs nothing. Adopt the
identity before the first push, then commit the result, per ADR-0106:

    bash scripts/project-rename.sh <slug> <module-path> <apex-host> <image-registry>
    mise run gen

To contribute to the template and not adopt it, keep the repository name, and
this gate stays quiet."
