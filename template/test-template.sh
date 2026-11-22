#!/usr/bin/env bash
# Tests the making of a project, per TPL-0000: each fixture through `just init`, the refusals of its validator,
# and the equality of the two ways to make a project. It needs no network and no cluster.
set -euo pipefail
source "$(tabkit-ops lib)/bootstrap.sh"

FIXTURES="template/test/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

step "copying the tracked files"
SRC="$WORK/template"
mkdir -p "$SRC"
git ls-files -z | tar --null -T - -cf - | tar -x -C "$SRC"
git ls-files -z --others --exclude-standard | tar --null -T - -cf - | tar -x -C "$SRC" 2>/dev/null || true

# The project scope, as `nix flake new -t` copies it: every file but template/ and the workflow of the template.
flake_new() { # <out>
  mkdir -p "$1"
  (cd "$SRC" && tar --exclude=./template --exclude=./.github/workflows/template.yml -cf - .) | tar -x -C "$1"
  git -C "$1" init -q .
}

# A clone made from the GitHub template button: every file, template/ included.
clone() { # <out>
  mkdir -p "$1"
  (cd "$SRC" && tar -cf - .) | tar -x -C "$1"
  git -C "$1" init -q .
  git -C "$1" add -A
}

step "rejecting invalid fixtures"
for fixture in "$FIXTURES"/invalid/*.yml; do
  name="$(basename "$fixture" .yml)"
  out="$WORK/invalid-$name"
  flake_new "$out"
  if (cd "$out" && bash scripts/project-init.sh --answers "$ROOT/$fixture") >"$WORK/$name.log" 2>&1; then
    warn "${name}: init succeeded, so the validator accepted an invalid answer"
    FAILED=1
  else
    detail "${name}: $(grep -m1 -oE 'a (slug|project slug) is .*' "$WORK/$name.log" || tail -1 "$WORK/$name.log")"
  fi
done

OLD_MODULE="$(awk '/^module /{print $2; exit}' go.mod)"
OLD_REGISTRY="ghcr.io/tabmadi/sovereign-platform-template"
OLD_APEX="example.com"
OLD_NODE="example-dev-cp"
MACHINERY=(template scripts/project-rename.sh scripts/project-init.sh scripts/forge-mode.sh .github/workflows/template.yml)

# The paths of each mode: `<key>|<value>|<path>`, the same list as scripts/project-init.sh.
MODES="forge|forgejo|infra/runner
forge|forgejo|infra/forge-host
forge|forgejo|.forgejo
provisioning|hypervisor|infra/hypervisor
provisioning|opentofu|infra/opentofu"

mode_problems() { # <out> <fixture>
  local out="$1" fixture="$2" key value path chosen
  while IFS='|' read -r key value path; do
    chosen="$(yq -r ".${key} // \"\"" "$fixture")"
    case "$key" in
    forge) chosen="${chosen:-github}" ;;
    provisioning) chosen="${chosen:-opentofu}" ;;
    esac
    if [ "$chosen" = "$value" ] && [ ! -e "$out/$path" ]; then echo "${path} is missing for ${key} ${value}"; fi
    if [ "$chosen" != "$value" ] && [ -e "$out/$path" ]; then echo "${path} is present for ${key} ${chosen}"; fi
  done <<<"$MODES"
  if [ "$(yq -r '.forge // ""' "$fixture")" = forgejo ] && grep -lq '^ *permissions:' "$out"/.forgejo/workflows/*.yml; then
    echo "a workflow keeps a permissions block on forgejo"
  fi
  if [ "$(yq -r '.forge // ""' "$fixture")" = forgejo ] &&
    ! grep -qxF '${PullRequestTitle} (${PullRequestReference})' "$out/.forgejo/default_merge_message/SQUASH_TEMPLATE.md"; then
    echo "the squash template is missing on forgejo"
  fi
}

step "making a project from each valid fixture"
for fixture in "$FIXTURES"/valid/*.yml; do
  name="$(basename "$fixture" .yml)"
  out="$WORK/valid-$name"
  flake_new "$out"
  if ! (cd "$out" && bash scripts/project-init.sh --answers "$ROOT/$fixture") >"$WORK/$name.log" 2>&1; then
    warn "${name}: init failed: $(tail -3 "$WORK/$name.log" | tr '\n' ' ')"
    FAILED=1
    continue
  fi

  problems=()
  for literal in "$OLD_MODULE" "$OLD_REGISTRY" "$OLD_APEX" "$OLD_NODE"; do
    hits="$({ grep -rlF --exclude-dir=.git --exclude-dir=node_modules --binary-files=without-match \
      --exclude=tabkit.toml -- "$literal" "$out" 2>/dev/null || true; } | wc -l)"
    [ "$hits" -eq 0 ] || problems+=("${hits} file(s) still carry '${literal}'")
  done
  for f in "${MACHINERY[@]}"; do
    if [ -e "$out/$f" ]; then problems+=("init left behind ${f}"); fi
  done
  grep -q '^init ' "$out/justfile" && problems+=("the justfile keeps the init recipe")
  title="$(yq -r '.project_name // "Acme Platform"' "$fixture")"
  [ "$(head -1 "$out/README.md")" = "# ${title}" ] || problems+=("the README title is not ${title}")
  while IFS= read -r problem; do
    if [ -n "$problem" ]; then problems+=("$problem"); fi
  done < <(mode_problems "$out" "$fixture")

  if [ "${#problems[@]}" -eq 0 ]; then
    detail "${name}: clean"
  else
    warn "${name}:"
    printf '      %s\n' "${problems[@]}" >&2
    FAILED=1
  fi
done

step "comparing the two ways to make a project"
for name in defaults own-hardware; do
  out="$WORK/clone-$name"
  clone "$out"
  if ! (cd "$out" && bash scripts/project-init.sh --answers "$ROOT/$FIXTURES/valid/$name.yml") >"$WORK/clone-$name.log" 2>&1; then
    warn "${name}: init failed in a clone: $(tail -3 "$WORK/clone-$name.log" | tr '\n' ' ')"
    FAILED=1
    continue
  fi
  differences="$(diff -rq --exclude=.git "$WORK/valid-$name" "$out" 2>&1 || true)"
  if [ -n "$differences" ]; then
    warn "${name}: a clone and a flake copy differ after init:"
    printf '      %s\n' "$differences" >&2
    FAILED=1
  else
    detail "${name}: identical"
  fi
done

[ "$FAILED" -eq 0 ] || fail "the making of a project failed"
ok "every fixture makes a clean project, and both ways give the same files"
