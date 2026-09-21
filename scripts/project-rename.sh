#!/usr/bin/env bash
# Rename a freshly generated project (ADR-0106, ADR-0003).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

[ "$#" -eq 4 ] || fail "usage: project-rename.sh <project-slug> <module-path> <apex-host> <image-registry>"
slug="$1" module="$2" apex="$3" registry="$4"

# A forge-side "Use this template" copies the tree and runs nothing, so such a copy is indistinguishable from the template by content.
# The fallback is lint:project-identity's invariant: a repository whose name matches its module path owns its identity.
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
  # No remote. Either Copier is mid-generation — it writes the answers file before
  # it runs its tasks, and the output is not a git repository yet — or someone is
  # holding a bare clone of the template, where a rename would be a mistake.
  [ -f .copier-answers.yml ] ||
    fail "no origin remote and no .copier-answers.yml — nothing distinguishes this tree from the template"
elif [ "$(basename -s .git "$origin_url")" = "$(basename "$(awk '/^module /{print $2; exit}' go.mod)")" ]; then
  # The answers file is not an exemption: it is present for the whole life of a generated project, and treating it as one leaves this script armed to rewrite a name someone chose.
  fail "the repository name already matches the module path — this is the template, or a project that has already been renamed"
fi

# What the template calls itself. Read from go.mod rather than hard-coded, so a
# template that is itself renamed does not leave this script pointing at a name
# nothing uses.
old_module="$(awk '/^module /{print $2; exit}' go.mod)"
old_registry="ghcr.io/tabmadi/sovereign-platform-template"
old_apex="example.com"

[ "$old_module" != "$module" ] || fail "the module path is already ${module}"

# A generated project is not a git repository yet — Copier runs this before the first commit — so grep must be told which directories are not source.
step "renaming to ${slug}"
PRUNE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.rumdl_cache --binary-files=without-match)

replace() { # <from> <to>
  # `|` is the sed delimiter, so it is the one character an argument may not
  # carry unescaped. Nothing here can contain one — a module path, a host and a
  # registry namespace are all URL-shaped — but escaping it costs one expansion.
  local from="${1//|/\\|}" to="${2//|/\\|}"
  grep -rlZ -F "${PRUNE[@]}" -- "$1" . 2>/dev/null |
    xargs -0 -r sed -i "s|${from}|${to}|g"
}

replace "$old_module" "$module"
detail "module path → ${module}"
replace "$old_registry" "$registry"
detail "images → ${registry}"
# The environment hosts before the apex, so `dev.example.com` does not become
# `dev.<apex>.com` by way of the shorter match.
for env in dev staging prod; do
  replace "${env}.${old_apex}" "${env}.${apex}"
done
replace "mail.${old_apex}" "mail.${apex}"
replace "$old_apex" "$apex"
detail "hosts → ${apex}"

ok "renamed to ${slug} — run 'mise run gen' and 'mise run check' before the first commit"
