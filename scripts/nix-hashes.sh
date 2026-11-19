#!/usr/bin/env bash
# Writes the hashes of the two fixed-output derivations of flake.nix again: the Go modules and the subcharts.
# Renovate runs it after an update of go.sum or a Chart.lock, per ADR-0117. An engineer runs it after the same change.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootstrap.sh"

fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
system="$(nix eval --raw --impure --expr builtins.currentSystem)"

for output in go-modules helm-charts; do
  # The hash is the line after the `name` of the derivation in flake.nix.
  current="$(awk -v n="name = \"${output}\";" 'index($0, n) {f = 1} f && /outputHash = "/ {match($0, /sha256-[A-Za-z0-9+\/=]+/); print substr($0, RSTART, RLENGTH); exit}' flake.nix)"
  [ -n "$current" ] || fail "no outputHash for ${output} in flake.nix"
  sed -i "s|${current}|${fake}|" flake.nix
  got="$(nix build ".#packages.${system}.${output}" --no-link 2>&1 | sed -nE 's/.*got: +(sha256-[A-Za-z0-9+/=]+).*/\1/p' | head -1)"
  sed -i "s|${fake}|${got:-$current}|" flake.nix
  if [ -z "$got" ]; then
    detail "${output}: unchanged"
  else
    detail "${output}: ${got}"
  fi
done
ok "flake.nix holds the current hashes"
