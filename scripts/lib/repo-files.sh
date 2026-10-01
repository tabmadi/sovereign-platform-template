#!/usr/bin/env bash
# The files this repository's gates act on, enumerated one way for all of them.

if [[ -n "${__REPO_FILES_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__REPO_FILES_LOADED=1

# repo_source prints `git` or `find`: the source that the enumerators use.
repo_source() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git'
  else
    printf 'find'
  fi
}

# existing drops index entries whose working-tree file is gone. `git ls-files` lists a deleted path until the deletion is staged.
# shfmt, shellcheck, and sha256sum all fail on a missing file.
existing() {
  while IFS= read -r -d '' f; do
    if [[ -e "$f" ]]; then printf '%s\0' "$f"; fi
  done
}

# sh_files and repo_files are NUL-delimited, and they include untracked paths that are not ignored.
# A gate cannot check a file it cannot see, and a new generated file is still drift.
sh_files() {
  if [[ "$(repo_source)" == "git" ]]; then
    {
      git ls-files -z '*.sh'
      git ls-files -z --others --exclude-standard '*.sh'
    } | existing
    return
  fi
  prune_find -name '*.sh'
}

repo_files() {
  if [[ "$(repo_source)" == "git" ]]; then
    {
      git ls-files -z
      git ls-files -z --others --exclude-standard
    } | existing
    return
  fi
  prune_find
}

# prune_find is `find` without the vendored and generated trees that .gitignore keeps out of `git ls-files`.
prune_find() {
  find . \
    -type d \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name vendor \) -prune \
    -o -type f "$@" -print0
}
