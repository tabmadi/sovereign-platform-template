#!/usr/bin/env bash
# Render the machinery table in docs/reference/build-path.md from the tasks themselves (ADR-0000 principle 2): every
# task a workflow or hook reaches, the failure class its description names, and where it runs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

DOC="docs/reference/build-path.md"
BEGIN="<!-- machinery:begin -->"
END="<!-- machinery:end -->"
grep -qF "$BEGIN" "$DOC" || fail "${DOC} has no ${BEGIN} marker"

tasks="$(for f in .mise.toml .config/mise/conf.d/*.toml; do
  [ -f "$f" ] || continue
  yq -p toml -o json '.tasks // {}' "$f"
done | jq -s 'add')"

# Each entry point and the tasks it names, as "<file> <task>" lines.
roots="$(grep -oE 'mise run [a-z][a-z0-9:.-]*' .github/workflows/*.yml .lefthook.yml |
  sed -E 's|^([^:]+):mise run |\1 |' | sort -u)"

rows="$(jq -rn --argjson t "$tasks" --arg roots "$roots" '
  def reach($name): [$name] + ([($t[$name].depends // [])[] | reach(.)] | add // []);
  [$roots | split("\n")[] | select(length > 0) | split(" ") as [$file, $task]
    | select($t[$task] != null) | reach($task)[] | {task: ., from: ($file | split("/") | last)}]
  | group_by(.task)
  | map({task: .[0].task, from: ([.[].from] | unique | join(", "))})
  | map(select($t[.task].run != null))
  | map(. + {owns: ($t[.task].description // "")})
  | .[]
  | "\(.task)\t\(.owns)\t\(.from)"')"

missing="$(awk -F'\t' '$2 == "" {print $1}' <<<"$rows")"
[ -z "$missing" ] || fail "tasks a workflow or hook reaches carry no description — the failure class they own:
$(sed 's/^/  /' <<<"$missing")"

table="$(
  printf '| Task | Owns | Reached from |\n| --- | --- | --- |\n'
  awk -F'\t' '{gsub(/\|/, "\\|", $2); printf "| `%s` | %s | %s |\n", $1, $2, $3}' <<<"$rows"
)"

awk -v begin="$BEGIN" -v end="$END" -v table="$table" '
  $0 == begin { print; print ""; print table; print ""; skip = 1; next }
  $0 == end { skip = 0 }
  !skip { print }
' "$DOC" >"${DOC}.tmp"
mv "${DOC}.tmp" "$DOC"
ok "${DOC}: $(wc -l <<<"$rows" | tr -d ' ') mechanisms"
