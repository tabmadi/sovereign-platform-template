#!/usr/bin/env bash
# Fail when a project created from this template still wears the template's identity (ADR-0106, ADR-0003).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

# The gate and its test name the footprints by definition, the answers file names the template it came from, and a `*.local.md` file is one engineer's untracked notes.
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache --exclude=.copier-answers.yml --exclude='*.local.md'
  --exclude=lint-project-identity.sh --exclude=test-template.sh --binary-files=without-match)

# The template's footprints; `project-rename.sh` rewrites this set before the first push.
FOOTPRINTS=(
  "github.com/tabmadi/sovereign-platform-template"
  "ghcr.io/tabmadi/sovereign-platform-template"
  "example.com"
  "example-dev-cp"
  "example-staging-cp"
  "example-prod-cp"
)

# A generated project has an identity on the record. The file's presence is not the
# proof: it is present for the whole life of the project, so the gate checks that the
# recorded answers were APPLIED and that no footprint survives.
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
    problems+=("no Talos node is named '${project_slug}-…' — the inventory still carries the template's names")
  for footprint in "${FOOTPRINTS[@]}"; do
    # The brace group absorbs grep's 1 under `pipefail`, which would otherwise end the run.
    hits="$({ grep -rlF "${PRUNE[@]}" -- "$footprint" . 2>/dev/null || true; } | wc -l)"
    [ "$hits" -eq 0 ] || problems+=("${hits} file(s) still carry '${footprint}'")
  done

  if [ "${#problems[@]}" -gt 0 ]; then
    warn "this project still wears the template's identity:"
    printf '  · %s\n' "${problems[@]}" >&2
    fail "adopt the identity with scripts/project-rename.sh, then run 'mise run gen'"
  fi
  ok "identity recorded and applied (${project_slug})"
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
module_hits="$({ grep -rlF "${PRUNE[@]}" -- "$module_path" . 2>/dev/null || true; } | wc -l)"
apex_hits="$({ grep -rlF "${PRUNE[@]}" -- "example.com" . 2>/dev/null || true; } | wc -l)"
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
