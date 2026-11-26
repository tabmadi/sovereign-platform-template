# shellcheck shell=bash disable=SC2154
# The local cache of the lab, per ADR-0208: the Nix paths under GC roots, and the node images in a private zot.
# lab.sh sources it after it sets `work`, `schematic`, and `version`.

roots="$work/roots"
registry_name="hypervisor-lab-zot"
registry_port="${LAB_REGISTRY_PORT:-5010}"
# The address that the nodes use for the workstation. QEMU forwards it, also when the VM has no internet.
registry_guest="10.0.2.100:5000"
registry_image="$(sed -n 's/^ZOT_IMAGE="\(.*\)"/\1/p' "$(tabkit-ops lib)/cluster.sh")"
registry_upstreams=(docker.io factory.talos.dev gcr.io ghcr.io quay.io registry.k8s.io)
min_free_gb="${LAB_MIN_FREE_GB:-20}"
min_memory_mb="${LAB_MIN_MEMORY_MB:-16384}"
memory_floor_mb="${LAB_MEMORY_FLOOR_MB:-2048}"

lab_nodes=(hypervisor-lab hypervisor-lab-broken hypervisor-lab-next)
lab_targets=(
  .#full-tier-lab
  .#full-tier-lab-installer
  .#hypervisor-lab-key
  .#labConfigurations.hypervisor-lab.config.system.build.diskoScript
)
for node in "${lab_nodes[@]}"; do
  lab_targets+=(".#labConfigurations.${node}.config.system.build.toplevel" ".#deploy.nodes.${node}.profiles.system.path")
done

available_memory_mb() { awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo; }

check_resources() {
  local free memory
  free="$(df -BG --output=avail "$work" | tail -1 | tr -dc 0-9)"
  [ "$free" -ge "$min_free_gb" ] || {
    echo "FAIL: ${free} GB of disk is free in ${work}, and the lab needs ${min_free_gb} GB" >&2
    exit 1
  }
  memory="$(available_memory_mb)"
  [ "$memory" -ge "$min_memory_mb" ] || {
    echo "FAIL: ${memory} MiB of memory is available, and the lab needs ${min_memory_mb} MiB. Stop other clusters first" >&2
    exit 1
  }
}

# Stops the lab before the workstation runs short of memory. The cap of the scope covers only the lab itself.
memory_guard() { # <pid>
  while sleep 5; do
    if [ "$(available_memory_mb)" -lt "$memory_floor_mb" ]; then
      echo "FAIL: the workstation has less than ${memory_floor_mb} MiB of memory available, so the lab stops" >&2
      kill -TERM "$1"
      return
    fi
  done
}

lab_images() {
  talosctl image k8s-bundle
  printf 'factory.talos.dev/metal-installer/%s:%s\n' "$schematic" "$version"
}

image_cached() { skopeo inspect --raw --tls-verify=false "docker://127.0.0.1:${registry_port}/$1" >/dev/null 2>&1; }

registry_start() {
  docker image inspect "$registry_image" >/dev/null 2>&1 || {
    [ "$mode" = online ] || {
      echo "FAIL: the image ${registry_image} is missing. Run the lab once with the internet" >&2
      exit 1
    }
    docker pull -q "$registry_image" >/dev/null
  }
  mkdir -p "$work/registry/data"
  cat >"$work/registry/config.json" <<'EOF'
{"distSpecVersion":"1.1.1","storage":{"rootDirectory":"/var/lib/registry/data","gc":false,"dedupe":false},"http":{"address":"0.0.0.0","port":"5000"},"log":{"level":"error"}}
EOF
  docker rm -f "$registry_name" >/dev/null 2>&1 || true
  docker run -d --rm --name "$registry_name" --user "$(id -u):$(id -g)" -p "127.0.0.1:${registry_port}:5000" \
    -v "$work/registry:/var/lib/registry" -v "$work/registry/config.json:/etc/zot/config.json:ro" \
    "$registry_image" >/dev/null
  retry 24 curl -fsS -o /dev/null "http://127.0.0.1:${registry_port}/v2/"
}

registry_stop() { docker rm -f "$registry_name" >/dev/null 2>&1 || true; }

# Each item is skipped when the cache holds it, so a run after a network failure continues from there.
prepare_cache() {
  local path index=0 image
  mkdir -p "$roots"
  # One build evaluates the flake once. A build for each target would evaluate the same machines again each time.
  rm -f "$roots"/target*
  nix build --max-jobs auto --out-link "$roots/target" "${lab_targets[@]}"
  nix develop --profile "$roots/dev-shell" --command true
  # Each run adds a generation of the profile, and an old one only holds an old dev shell.
  nix profile wipe-history --profile "$roots/dev-shell"
  rm -f "$roots"/input-*
  while read -r path; do
    index=$((index + 1))
    nix-store --add-root "$roots/input-${index}" --realise "$path" >/dev/null
  done < <(nix flake archive --json | jq -r '.. | .path? // empty' | sort -u)
  while read -r image; do
    image_cached "$image" && continue
    printf 'caching %s\n' "$image"
    skopeo copy -q --retry-times 3 --dest-tls-verify=false --override-os linux --override-arch amd64 \
      "docker://${image}" "docker://127.0.0.1:${registry_port}/${image}"
  done < <(lab_images)
}

# A missing item stops the run here, with its name, and not later as a timeout on a node.
verify_cache() {
  local plan image missing=()
  plan="$(nix build --offline --dry-run "${lab_targets[@]}" 2>&1)" || {
    printf '%s\n' "$plan" >&2
    echo "FAIL: the Nix cache cannot serve the lab. Run the lab once with the internet" >&2
    exit 1
  }
  if grep -q 'will be' <<<"$plan"; then
    printf '%s\n' "$plan" >&2
    echo "FAIL: the Nix paths above are missing. Run the lab once with the internet" >&2
    exit 1
  fi
  while read -r image; do
    image_cached "$image" || missing+=("$image")
  done < <(lab_images)
  [ "${#missing[@]}" -eq 0 ] || {
    printf 'missing image: %s\n' "${missing[@]}" >&2
    echo "FAIL: the image cache is not complete. Run the lab once with the internet" >&2
    exit 1
  }
}

# The mirrors of the lab nodes. skipFallback makes a missing image an error, so a pass proves that the cache is complete.
write_mirror_patch() { # <file>
  local upstream
  {
    printf 'machine:\n  registries:\n    mirrors:\n'
    for upstream in "${registry_upstreams[@]}"; do
      printf '      %s:\n        endpoints: ["http://%s/v2/%s"]\n        overridePath: true\n        skipFallback: true\n' \
        "$upstream" "$registry_guest" "$upstream"
    done
  } >"$1"
}
