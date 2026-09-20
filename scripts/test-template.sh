#!/usr/bin/env bash
# Exercise this repository's own generation (ADR-0106).

set -euo pipefail
# shellcheck source=lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
FIXTURES="test/template/fixtures"

# A generated project inherits this script and its fixtures but has no `copier.yml`,
# so there is nothing for it to generate from. Reporting that is honest; failing
# would make every generated project's `mise run test` red on day one.
if [ ! -f copier.yml ]; then
  ok "no copier.yml — not a template, nothing to generate"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# Copier renders from a git ref, so without the snapshot this tests the last commit rather than the working tree.
step "snapshotting the working tree"
SRC="$WORK/template"
mkdir -p "$SRC"
git ls-files -z | tar --null -T - -cf - | tar -x -C "$SRC"
git ls-files -z --others --exclude-standard | tar --null -T - -cf - | tar -x -C "$SRC" 2>/dev/null || true
git -C "$SRC" init -q .
git -C "$SRC" add -A
git -C "$SRC" -c user.email=test@local -c user.name=test commit -qm "template under test"
SRC_REF="$(git -C "$SRC" rev-parse --short HEAD)"
detail "ref ${SRC_REF}"

step "rejecting invalid fixtures"
for fixture in "$FIXTURES"/invalid/*.yml; do
  name="$(basename "$fixture" .yml)"
  out="$WORK/invalid-$name"
  if mise x -- copier copy --trust --defaults --data-file "$fixture" "$SRC" "$out" >"$WORK/$name.log" 2>&1; then
    warn "✗ ${name}: generation SUCCEEDED — the validator accepted an invalid answer"
    FAILED=1
  else
    # Surface the refusal, so a fixture failing for an unrelated reason is not mistaken for a validator doing its job.
    # Anchoring on `ValueError:` separates the rendered message from the f-string in copier's traceback.
    reason="$(grep -m1 -oE "ValueError: Validation error for question '[^']*': .*" "$WORK/$name.log" |
      sed 's/^ValueError: //' || true)"
    if [ -z "$reason" ]; then
      warn "✗ ${name}: rejected, but not by a validator — $(tail -1 "$WORK/$name.log")"
      FAILED=1
    else
      detail "${name} — ${reason}"
    fi
  fi
done

# What the template calls itself, read from the tree so a renamed template does not
# leave these pointing at a name nothing uses.
OLD_MODULE="$(awk '/^module /{print $2; exit}' go.mod)"
OLD_REGISTRY="ghcr.io/tabmadi/sovereign-platform-template"
OLD_APEX="example.com"
MACHINERY=(copier.yml .copier-answers.yml.jinja .template-version scripts/project-rename.sh scripts/project-init.sh)

step "generating valid fixtures"
for fixture in "$FIXTURES"/valid/*.yml; do
  name="$(basename "$fixture" .yml)"
  out="$WORK/valid-$name"
  if ! mise x -- copier copy --trust --defaults --data-file "$fixture" "$SRC" "$out" >"$WORK/$name.log" 2>&1; then
    warn "✗ ${name}: generation failed — $(tail -3 "$WORK/$name.log" | tr '\n' ' ')"
    FAILED=1
    continue
  fi

  problems=()
  # The template's identity must not survive anywhere in the output.
  for literal in "$OLD_MODULE" "$OLD_REGISTRY" "$OLD_APEX"; do
    # `pipefail` makes a grep that matches nothing fail the whole pipeline, and an
    # assignment takes the pipeline's status — so the success case would abort the
    # script under `set -e`. The brace group absorbs grep's 1 before `wc` sees it.
    hits="$({ grep -rlF --exclude-dir=.git --exclude-dir=node_modules --binary-files=without-match \
      -- "$literal" "$out" 2>/dev/null || true; } | wc -l)"
    [ "$hits" -eq 0 ] || problems+=("${hits} file(s) still carry '${literal}'")
  done
  # Nothing once-only may survive into a product repository.
  for f in "${MACHINERY[@]}"; do
    # `[ … ] && arr+=(…)` returns 1 when the test is false, which `set -e` treats as
    # the loop body failing. An `if` says the same thing and cannot.
    if [ -e "$out/$f" ]; then problems+=("generation machinery left behind: ${f}"); fi
  done
  # The pin is the whole interface to `copier update`.
  [ -f "$out/.copier-answers.yml" ] || problems+=("no .copier-answers.yml")
  grep -q "^_commit:" "$out/.copier-answers.yml" 2>/dev/null || problems+=("no _commit in .copier-answers.yml")

  if [ "${#problems[@]}" -eq 0 ]; then
    detail "${name} — clean"
  else
    warn "✗ ${name}:"
    printf '      %s\n' "${problems[@]}" >&2
    FAILED=1
  fi
done

# Only `_src_path` may differ: Copier records the path it generated from, a local directory here, while `project:init` writes the canonical remote.
step "comparing the two adoption paths"
PATH_B="$WORK/valid-defaults"
PATH_A="$WORK/path-a"
mkdir -p "$PATH_A"
git -C "$SRC" archive HEAD | tar -x -C "$PATH_A"
echo "$SRC_REF" >"$PATH_A/.template-version"
(
  cd "$PATH_A"
  git init -q .
  git remote add origin "git@github.com:acme/acmeplat.git"
  bash scripts/project-init.sh "Acme Platform" acmeplat github.com/acme/acmeplat \
    acmeplat.example ghcr.io/acme/acmeplat
) >"$WORK/path-a.log" 2>&1 || {
  warn "✗ project:init failed — $(tail -3 "$WORK/path-a.log" | tr '\n' ' ')"
  FAILED=1
}

if [ -d "$PATH_B" ]; then
  differences="$(diff -rq --exclude=.git "$PATH_B" "$PATH_A" 2>&1 |
    grep -v '\.copier-answers\.yml differ$' || true)"
  answers_diff="$(diff "$PATH_B/.copier-answers.yml" "$PATH_A/.copier-answers.yml" 2>/dev/null |
    grep -E '^[<>]' | grep -vE '^[<>] _src_path:' || true)"
  if [ -n "$differences" ] || [ -n "$answers_diff" ]; then
    warn "✗ the two paths diverge — copier update's merge baseline would be wrong:"
    [ -n "$differences" ] && printf '      %s\n' "$differences" >&2
    [ -n "$answers_diff" ] && printf '      %s\n' "$answers_diff" >&2
    FAILED=1
  else
    detail "identical but for _src_path"
  fi
fi

# Minutes rather than seconds, with no warm caches. Off by default; the nightly job sets DEEP.
if [ -n "${DEEP:-}" ] && [ -d "$PATH_B" ]; then
  step "running the generated project's own gates (DEEP)"
  if (
    cd "$PATH_B" && mise trust --quiet >/dev/null 2>&1
    mise run check
  ) >"$WORK/deep.log" 2>&1; then
    detail "check passed inside the generated project"
  else
    warn "✗ the generated project fails its own check:"
    tail -20 "$WORK/deep.log" | sed 's/^/      /' >&2
    FAILED=1
  fi
fi

echo
[ "$FAILED" -eq 0 ] || fail "template generation is broken — see the failures above"
ok "template generation is sound"
