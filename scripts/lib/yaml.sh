# shellcheck shell=bash

if [[ -n "${__YAML_SH_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__YAML_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# yaml_scalar_line <file> <dotted.path>
# Echoes the 1-based line of the scalar, or nothing when the path is not a block-style key in the file.
yaml_scalar_line() {
  awk -v target="${2#.}" '
    # Track the block path by indentation: pop every frame at or below the indent of this line, then push this key.
    match($0, /^[[:space:]]*[A-Za-z0-9_.-]+:/) {
      line = $0
      indent = match(line, /[^ ]/) - 1
      key = line; sub(/^[[:space:]]*/, "", key); sub(/:.*/, "", key)
      while (depth > 0 && indents[depth] >= indent) depth--
      depth++
      indents[depth] = indent
      keys[depth] = key
      path = keys[1]
      for (i = 2; i <= depth; i++) path = path "." keys[i]
      if (path == target) { print NR; exit }
    }
  ' "$1"
}

# Returns 1 and leaves the file unchanged when the path is absent, so a caller can skip a missing key.
# A path that yq sees but the walk cannot reach is a hard failure. Otherwise a promotion fails with no error.
yaml_set_scalar() {
  local file="$1" path="$2" value="$3" line

  [[ -f "$file" ]] || return 1
  # By tag, not by value: `digest: ""` is a key before its first write, not an absent key.
  [[ "$(yq "${path} | tag" "$file" 2>/dev/null)" != "!!null" ]] || return 1

  line="$(yaml_scalar_line "$file" "$path")"
  if [[ ! "$line" =~ ^[0-9]+$ ]]; then
    fail "${file}: ${path} exists but is not a block-style key, so it cannot be edited in place"
  fi

  # Rewrite the value between the key and any trailing comment. The indentation, the key, and the comment stay the same.
  # The write goes through a temp file, so a failure cannot truncate a committed values file.
  local tmp
  tmp="$(mktemp)"
  awk -v n="$line" -v v="$value" '
    NR != n { print; next }
    {
      key = $0; sub(/:.*/, ":", key)
      rest = substr($0, length(key) + 1)
      comment = (match(rest, /#/)) ? substr(rest, RSTART) : "" # lint:comments-allow
      printf "%s \"%s\"%s%s\n", key, v, (comment == "" ? "" : "   "), comment
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}
