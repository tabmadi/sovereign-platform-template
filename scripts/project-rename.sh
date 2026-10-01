#!/usr/bin/env bash
# Rename a newly generated project, per ADR-0106 and ADR-0003.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

[ "$#" -eq 4 ] || fail "usage: project-rename.sh <project-slug> <module-path> <apex-host> <image-registry>"
slug="$1" module="$2" apex="$3" registry="$4"

# A forge-side `Use this template` copies the tree and runs nothing, so by content such a copy looks the same as the template.
# The fallback is the lint:project-identity invariant: a repository whose name matches its module path owns its identity.
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
  # No remote. Either Copier is generating: it writes the answers file before its tasks, and the output is not a git repository yet.
  # Or someone holds a bare clone of the template, where a rename would be a mistake.
  [ -f .copier-answers.yml ] ||
    fail "no origin remote and no .copier-answers.yml. Nothing separates this tree from the template"
elif [ "$(basename -s .git "$origin_url")" = "$(basename "$(awk '/^module /{print $2; exit}' go.mod)")" ]; then
  # The answers file is not an exemption. It is present for the whole life of a generated project.
  # As an exemption, it would leave this script able to rewrite a name that someone chose.
  fail "the repository name already matches the module path. This is the template, or a project that is already renamed"
fi

# What the template calls itself. Read from go.mod, not hard-coded, so a renamed template does not leave this script pointing at an unused name.
old_module="$(awk '/^module /{print $2; exit}' go.mod)"
old_registry="ghcr.io/tabmadi/sovereign-platform-template"
old_apex="example.com"

[ "$old_module" != "$module" ] || fail "the module path is already ${module}"

# A generated project is not a git repository yet, because Copier runs this before the first commit. So grep must be told which directories are not source.
# The identity gate and its test name the template's footprints, so the rename leaves them alone. A rename would turn the gate against the project it protects.
step "renaming to ${slug}"
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache
  --exclude=lint-project-identity.sh --exclude=test-template.sh --binary-files=without-match)

replace() { # <from> <to>
  # `|` is the sed delimiter, so an argument cannot contain it unescaped. A module path, a host, and a registry namespace are URL-shaped,
  # so none contains one. The escape costs one expansion.
  local from="${1//|/\\|}" to="${2//|/\\|}"
  grep -rlZ -F "${PRUNE[@]}" -- "$1" . 2>/dev/null |
    xargs -0 -r sed -i "s|${from}|${to}|g"
}

# Argo CD reconciles from the project's own forge, per ADR-0102, and the template's URL is not that forge.
# This runs before the module path, whose replacement would turn it into the GitHub URL of the same name.
replace "https://${old_module}.git" "https://forge.${apex}/platform/${slug}.git"
detail "GitOps source → forge.${apex}/platform/${slug}"
replace "$old_module" "$module"
detail "module path → ${module}"
replace "$old_registry" "$registry"
detail "images → ${registry}"
# The environment hosts before the apex, so the shorter match does not turn `dev.example.com` into `dev.<apex>.com`.
for env in dev staging prod; do
  replace "${env}.${old_apex}" "${env}.${apex}"
done
replace "mail.${old_apex}" "mail.${apex}"
replace "$old_apex" "$apex"
detail "hosts → ${apex}"

# Talos names a node {project}-{env}-{role}, per ADR-0003: `<slug>-dev-cp-1`, never `example-`.
for f in infra/talos/inventory/*/nodes.yml; do
  [ -f "$f" ] || continue
  sed -i "s|example-|${slug}-|g" "$f"
done
detail "Talos inventory → ${slug}-<env>-<role>"

ok "renamed to ${slug}. Run 'mise run gen' and 'mise run check' before the first commit"
