#!/usr/bin/env bash
# Renames a new project, per ADR-0117 and ADR-0003. `just init` runs it once.
set -euo pipefail
source "$(tabkit-ops lib)/bootstrap.sh"

[ "$#" -eq 4 ] || fail "usage: project-rename.sh <project-slug> <module-path> <apex-host> <image-registry>"
slug="$1" module="$2" apex="$3" registry="$4"

# What the template calls itself. Read from go.mod, not hard-coded, so a renamed template does not leave this script pointing at an unused name.
old_module="$(awk '/^module /{print $2; exit}' go.mod)"
old_registry="ghcr.io/tabmadi/sovereign-platform-template"
old_apex="example.com"

[ "$old_module" != "$module" ] || fail "the module path is already ${module}"

# A new project can have no git repository yet, so grep must be told which directories are not source.
# The identity gate and its test name the template's footprints, so the rename leaves them alone. A rename would turn the gate against the project it protects.
step "renaming to ${slug}"
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache
  --exclude=tabkit.toml --exclude-dir=template --binary-files=without-match)

replace() { # <from> <to>
  # `|` is the sed delimiter, so an argument cannot contain it unescaped. A module path, a host, and a registry namespace are URL-shaped,
  # so none contains one. The escape costs one expansion.
  local from="${1//|/\\|}" to="${2//|/\\|}"
  # A name that no file holds is not an error. A project that deleted the files with that name, such as an unused
  # environment, is updated with the same rename.
  { grep -rlZ -F "${PRUNE[@]}" -- "$1" . 2>/dev/null || true; } |
    xargs -0 -r sed -i "s|${from}|${to}|g"
}

# Argo CD reconciles from the project's own forge, per ADR-0116, and the template's URL is not that forge.
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

# The allow-list is generated in byte order, and the registry namespace is one of its sort keys. So the rename sorts it again.
allowlist="infra/gitops/platform/image-allowlist.yaml"
if [ -f "$allowlist" ]; then
  {
    grep -v '^    - ' "$allowlist"
    grep '^    - ' "$allowlist" | LC_ALL=C sort -u
  } >"${allowlist}.sorted"
  mv "${allowlist}.sorted" "$allowlist"
  detail "image allow-list sorted for ${registry}"
fi

# A generated project does not keep the template's own tasks, per ADR-0117, so the table that includes them goes too.

ok "renamed to ${slug}. Run 'just gen' and 'just check' before the first commit"
