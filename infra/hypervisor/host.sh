#!/usr/bin/env bash
# The hypervisor's own network, per ADR-0200: two bridges, DHCP reservations, and NAT. Every file is rendered from
# hypervisor.env and the inventory, so no address is written twice. `render` writes them to a directory for review.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
source "$here/lib.sh"

usage() { fail "usage: host.sh <render <dir>|install>"; }
[ "$#" -ge 1 ] || usage

slug="$(awk '$1 == "project_slug:" {print $2; exit}' .copier-answers.yml 2>/dev/null)"
[ -n "$slug" ] || fail "no project_slug in .copier-answers.yml"

# The guests beside the nodes. Each kit's own file holds its address, and an absent kit has no guest here.
guests=()
if [ -f "$here/../forge-host/forge.env" ]; then
  guests+=("${slug}-${ENVIRONMENT}-forge $(awk -F'[=@]' '$1 == "FORGE_SSH" {print $3}' "$here/../forge-host/forge.env")")
fi
if [ -f "$here/../runner/runner.env" ]; then
  guests+=("${slug}-${ENVIRONMENT}-runner $(awk -F= '$1 == "RUNNER_ADDRESS" {print $2}' "$here/../runner/runner.env")")
fi
forge_address=""
for g in "${guests[@]}"; do
  case "$g" in *-forge\ *) forge_address="${g##* }" ;; esac
done

# A project adds what the template cannot know in `extra/`. Examples are another guest and another public address.
# A file there has the name of the file it extends, and it is added as it is. So it carries its own DNAT and MASQUERADE pairs.
extra_file() { # <name>
  if [ -f "$here/extra/$1" ]; then cat "$here/extra/$1"; fi
}
add_extra() { # <rendered file> <extra name>
  extra_file "$2" >>"$1"
}

render() { # <dir>
  local dir="$1" edge entry name address subnet
  mkdir -p "$dir"
  subnet="${PRIVATE_GATEWAY%.*}.0/${PRIVATE_PREFIX}"
  edge="$(nodes | head -1 | cut -d' ' -f2)"

  cat >"$dir/${PUBLIC_BRIDGE}" <<EOF
# The routed public subnet. Installed at /etc/network/interfaces.d/${PUBLIC_BRIDGE}. Rendered by infra/hypervisor/host.sh.
auto ${PUBLIC_BRIDGE}
iface ${PUBLIC_BRIDGE} inet static
  address ${PUBLIC_BRIDGE_ADDRESS}
  bridge-ports none
  bridge-stp off
  bridge-fd 0
EOF
  add_extra "$dir/${PUBLIC_BRIDGE}" "${PUBLIC_BRIDGE}"

  cat >"$dir/${PRIVATE_BRIDGE}" <<EOF
# The private network of every node and VM. Installed at /etc/network/interfaces.d/${PRIVATE_BRIDGE}.
auto ${PRIVATE_BRIDGE}
iface ${PRIVATE_BRIDGE} inet static
  address ${PRIVATE_GATEWAY}/${PRIVATE_PREFIX}
  bridge-ports none
  bridge-stp off
  bridge-fd 0
EOF

  {
    echo "# DHCP for ${PRIVATE_BRIDGE}. Installed at /etc/dnsmasq.d/${slug}.conf. A reservation is keyed by MAC, so a rebuilt VM keeps its address."
    echo "interface=${PRIVATE_BRIDGE}"
    echo "bind-interfaces"
    echo "except-interface=lo"
    echo "dhcp-range=${DHCP_RANGE},12h"
    echo "dhcp-option=option:router,${PRIVATE_GATEWAY}"
    echo "dhcp-option=option:dns-server,${DNS_SERVERS}"
    while read -r name address; do
      echo "dhcp-host=$(vm_mac "$address"),${name},${address}"
    done < <(
      nodes
      for entry in "${guests[@]}"; do echo "$entry"; done
    )
  } >"$dir/dnsmasq.conf"
  add_extra "$dir/dnsmasq.conf" dnsmasq.conf

  {
    echo "# NAT on the hypervisor. Installed at /etc/iptables/rules.v4, which iptables-persistent restores at boot."
    echo "# Each public address is a DNAT rule. The OUTPUT copy makes the host reach a public address where a client does."
    echo "*nat"
    echo ":PREROUTING ACCEPT [0:0]"
    echo ":INPUT ACCEPT [0:0]"
    echo ":OUTPUT ACCEPT [0:0]"
    echo ":POSTROUTING ACCEPT [0:0]"
    if [ -n "$PUBLIC_EDGE" ]; then
      echo "# The cluster edge. Traefik answers on its node ports."
      for pair in "80:${EDGE_HTTP_NODEPORT}" "443:${EDGE_HTTPS_NODEPORT}"; do
        for chain in PREROUTING OUTPUT; do
          echo "-A ${chain} -d ${PUBLIC_EDGE}/32 -p tcp --dport ${pair%:*} -j DNAT --to-destination ${edge}:${pair#*:}"
        done
        echo "-A POSTROUTING -s ${subnet} -d ${edge}/32 -p tcp --dport ${pair#*:} -j MASQUERADE"
      done
    fi
    if [ -n "$PUBLIC_FORGE" ] && [ -n "$forge_address" ]; then
      echo "# The forge. 2222 is its SSH transport, apart from the host's own 22."
      for port in 80 443 2222; do
        for chain in PREROUTING OUTPUT; do
          echo "-A ${chain} -d ${PUBLIC_FORGE}/32 -p tcp --dport ${port} -j DNAT --to-destination ${forge_address}:${port}"
        done
        echo "-A POSTROUTING -s ${subnet} -d ${forge_address}/32 -p tcp --dport ${port} -j MASQUERADE"
      done
    fi
    extra_file nat.rules
    echo "# The MASQUERADE rules above are the hairpin. A VM that reaches a public address of this network arrives with a"
    echo "# private source, and without them the reply would skip this host."
    if [ -n "$PUBLIC_MAIL" ]; then
      echo "# Mail leaves on one address whose PTR matches the HELO name of maddy, per ADR-0307."
      echo "-A POSTROUTING -s ${subnet} -p tcp --dport 25 -j SNAT --to-source ${PUBLIC_MAIL}"
    fi
    echo "-A POSTROUTING -s ${subnet} ! -d ${subnet} -j MASQUERADE"
    echo "COMMIT"
  } >"$dir/rules.v4"
}

case "$1" in
render)
  [ "$#" -eq 2 ] || usage
  render "$2"
  ok "rendered into $2"
  ;;
install)
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  render "$work"
  step "installing the bridges, DHCP, and NAT on ${HYPERVISOR_SSH}"
  # The rules are tested before they replace the running set, so a broken file does not cut the host off.
  tar -C "$work" -cf - . | remote "set -e
    d=\$(mktemp -d) && tar -C \"\$d\" -xf -
    iptables-restore --test <\"\$d/rules.v4\"
    install -m 0644 \"\$d/${PUBLIC_BRIDGE}\" \"\$d/${PRIVATE_BRIDGE}\" /etc/network/interfaces.d/
    install -m 0644 \"\$d/dnsmasq.conf\" /etc/dnsmasq.d/${slug}.conf
    install -D -m 0644 \"\$d/rules.v4\" /etc/iptables/rules.v4
    ifreload -a
    iptables-restore <\"\$d/rules.v4\"
    sysctl -q -w net.ipv4.ip_forward=1
    systemctl restart dnsmasq && systemctl is-active --quiet dnsmasq
    rm -rf \"\$d\""
  ok "the host serves the network that infra/hypervisor/hypervisor.env describes"
  ;;
*) usage ;;
esac
