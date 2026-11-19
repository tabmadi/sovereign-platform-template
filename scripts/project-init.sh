#!/usr/bin/env bash
# Turns a copy of the template into a project, per ADR-0117 and ADR-0003: `just init`.
# It asks the seven questions, renames the project, applies the setup modes, and then removes itself.
#
#   just init                          asks each question, with the default in brackets
#   just init --answers <file.yml>     reads the answers from a file, and takes the default for a missing key
#   just init --defaults               takes every default
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

answers_file=""
interactive=1
while [ "$#" -gt 0 ]; do
  case "$1" in
  --answers)
    [ "$#" -ge 2 ] || fail "--answers needs a file"
    answers_file="$2"
    interactive=0
    shift 2
    ;;
  --defaults)
    interactive=0
    shift
    ;;
  *) fail "usage: just init [--answers <file.yml> | --defaults]" ;;
  esac
done
[ -t 0 ] || interactive=0

# The answer of one key: from the file, then from the person, then the default.
ask() { # <key> <question> <default>
  local key="$1" question="$2" default="$3" value=""
  if [ -n "$answers_file" ]; then
    value="$(yq -r ".${key} // \"\"" "$answers_file")"
  fi
  if [ -z "$value" ] && [ "$interactive" -eq 1 ]; then
    read -r -p "${question} [${default}]: " value
  fi
  printf '%s' "${value:-$default}"
}

project_name="$(ask project_name "The name of the product, as a person writes it" "Acme Platform")"
slug="$(ask project_slug "The project slug, per ADR-0003: 5 to 11 characters, unique, with no org prefix" "acmeplat")"
# The ADR-0003 grammar, checked here and later by `lint-naming`. A name is cheapest to fix before it is in a provider console.
[[ "$slug" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] ||
  fail "a slug is lower-case alphanumeric with single hyphens: ${slug}"
[ "${#slug}" -ge 5 ] && [ "${#slug}" -le 11 ] ||
  fail "a project slug is 5 to 11 characters: ${slug}"
module="$(ask module_path "The Go module path: the import path of the repository" "github.com/acme/${slug}")"
apex="$(ask apex_host "The apex host of the product. The environments are dev., staging., and prod. below it" "${slug}.example")"
registry="$(ask image_registry "The registry namespace of the published images, per ADR-0114" "ghcr.io/acme/${slug}")"
forge="$(ask forge "Where the pipelines run, per ADR-0116: github or forgejo" "github")"
[[ "$forge" =~ ^(github|forgejo)$ ]] || fail "the forge is github or forgejo: ${forge}"
provisioning="$(ask provisioning "How the nodes come to exist, per ADR-0200: terraform, provided, or hypervisor" "terraform")"
[[ "$provisioning" =~ ^(terraform|provided|hypervisor)$ ]] ||
  fail "the provisioning is terraform, provided, or hypervisor: ${provisioning}"

step "initialising ${project_name} as ${slug}"
bash scripts/project-rename.sh "$slug" "$module" "$apex" "$registry"

# The title of the README names the product. The rest of the README describes the template, and the welcome text says to rewrite it.
sed -i "1s|^# .*|# ${project_name}|" README.md

# The files of a setup mode that the project did not choose, per docs/reference/modes.md.
drop_mode() { # <answer> <value> <path>
  if [ "$1" != "$2" ] && [ -e "$3" ]; then
    rm -rf -- "$3"
    detail "removed ${3}, a file of the ${2} mode"
  fi
}
drop_mode "$forge" forgejo infra/runner
drop_mode "$forge" forgejo infra/forge-host
drop_mode "$provisioning" hypervisor infra/hypervisor
drop_mode "$provisioning" terraform infra/terraform

bash scripts/forge-mode.sh "$forge"

printf '%s\n' "# The identity of the project, per ADR-0003 and ADR-0117. \`just init\` writes it, and the scripts of infra/ read it." \
  "slug: ${slug}" "apex: ${apex}" "forge: ${forge}" "provisioning: ${provisioning}" >infra/project.yaml

# The template scope and the scripts that run once. A copy made with `nix flake new` has no template/ folder.
if [ -d template ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rm -r -q --cached template 2>/dev/null || true
  fi
  rm -rf template
  detail "removed template/"
fi
rm -f .github/workflows/template.yml .forgejo/workflows/template.yml scripts/project-rename.sh scripts/forge-mode.sh
# The init recipe goes with the script it calls.
sed -i '/^# Turn this copy into a project/,/^$/d' justfile

ok "initialised ${project_name}. Run 'just gen' and 'just check', then commit"
# This script goes last: bash can unlink a file it runs, but it cannot rewrite it in place.
rm -f -- "${BASH_SOURCE[0]}"
