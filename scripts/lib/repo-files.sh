#!/usr/bin/env bash
# The files this repository's gates act on, enumerated one way for all of them.

if [[ -n "${__REPO_FILES_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
__REPO_FILES_LOADED=1

# repo_source — prints `git` or `find`, whichever the enumerators will use.
repo_source() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git'
  else
    printf 'find'
  fi
}

# sh_files prints every shell script, NUL-delimited. Untracked-but-not-ignored counts, as it does for repo_files: a script the gate cannot see is a script the gate cannot hold.
sh_files() {
  if [[ "$(repo_source)" == "git" ]]; then
    git ls-files -z '*.sh'
    git ls-files -z --others --exclude-standard '*.sh'
    return
  fi
  prune_find -name '*.sh'
}

# repo_files prints every file a gate should consider, NUL-delimited. Untracked-but-not-ignored counts: a generated file that is new is still drift.
repo_files() {
  if [[ "$(repo_source)" == "git" ]]; then
    git ls-files -z
    git ls-files -z --others --exclude-standard
    return
  fi
  prune_find
}

# prune_find — `find` over the repository with the vendored and generated trees
# excluded, matching what .gitignore keeps out of `git ls-files`.
prune_find() {
  find . \
    -type d \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name vendor \) -prune \
    -o -type f "$@" -print0
}

# sh_source — the historical name, kept because the shell gates read well with it.
sh_source() { repo_source; }
