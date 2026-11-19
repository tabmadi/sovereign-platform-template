#!/usr/bin/env bash
# Render the machinery table in docs/reference/build-path.md from the recipes themselves, per ADR-0000 principle 2.
# It lists every recipe that a workflow, a check, or a hook reaches, the failure class its doc comment names, and where it runs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DOC="docs/reference/build-path.md"
BEGIN="<!-- machinery:begin -->"
END="<!-- machinery:end -->"
grep -qF "$BEGIN" "$DOC" || fail "${DOC} has no ${BEGIN} marker"

recipes="$(just --dump --dump-format json | jq '.recipes')"

# Each entry point and the recipes it names, as `<file> <recipe>` lines.
# A workflow step calls `just <recipe>`. A check of flake.nix runs `gate "<name>" "<recipes>"`. The pre-push hook runs `just ci`.
# The workflow of the template scope is left out, so a project and the template render the same table.
shopt -s nullglob
roots="$({
  grep -oE 'just [a-z][a-z0-9-]*' .github/workflows/*.yml .forgejo/workflows/*.yml | grep -v '/template\.yml:' |
    sed -E 's|^([^:]+):just |\1 |'
  sed -nE 's|.*gate "[a-z0-9-]+" "([a-z0-9 -]+)".*|\1|p' flake.nix | tr ' ' '\n' | sed 's|^|flake.nix |'
  echo "git hooks ci"
} | sort -u)"

rows="$(jq -rn --argjson t "$recipes" --arg roots "$roots" '
  def reach($name): [$name] + ([($t[$name].dependencies // [])[].recipe | reach(.)] | add // []);
  [$roots | split("\n")[] | select(length > 0) | capture("^(?<file>.+) (?<recipe>[a-z0-9-]+)$")
    | select($t[.recipe] != null) | .file as $file | reach(.recipe)[] | {recipe: ., from: ($file | split("/") | last)}]
  | group_by(.recipe)
  | map({recipe: .[0].recipe, from: ([.[].from] | unique | join(", "))})
  | map(select(($t[.recipe].body | length) > 0 and ($t[.recipe].private | not)))
  | map(. + {owns: ($t[.recipe].doc // "")})
  | .[]
  | "\(.recipe)\t\(.owns)\t\(.from)"')"

missing="$(awk -F'\t' '$2 == "" {print $1}' <<<"$rows")"
[ -z "$missing" ] || fail "recipes that a workflow, a check, or a hook reaches have no doc comment that names the failure class they own:
$(sed 's/^/  /' <<<"$missing")"

table="$(
  printf '| Recipe | Owns | Reached from |\n| --- | --- | --- |\n'
  awk -F'\t' '{gsub(/\|/, "\\|", $2); printf "| `%s` | %s | %s |\n", $1, $2, $3}' <<<"$rows"
)"

awk -v begin="$BEGIN" -v end="$END" -v table="$table" '
  $0 == begin { print; print ""; print table; print ""; skip = 1; next }
  $0 == end { skip = 0 }
  !skip { print }
' "$DOC" >"${DOC}.tmp"
mv "${DOC}.tmp" "$DOC"
ok "${DOC}: $(wc -l <<<"$rows" | tr -d ' ') mechanisms"
