# The VMs of the hypervisor and their network, per ADR-0208. Each VM is a QEMU unit on one private bridge. dnsmasq
# gives each VM the address that its MAC names, and the host routes the bridge to the internet through NAT.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.hypervisor;
  vms = lib.attrValues cfg.vms;
  subnet = "${lib.concatStringsSep "." (lib.take 3 (lib.splitString "." cfg.private.gateway))}.0/${toString cfg.private.prefix}";

  # The MAC holds the address in hex: 10.0.10.11 gets 0e:00:0a:00:0a:0b. So a rebuilt VM keeps its address.
  mac =
    address:
    "0e:00:"
    + lib.concatMapStringsSep ":" (
      o: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString (lib.toInt o)))
    ) (lib.splitString "." address);
  prefixOf = address: lib.concatStringsSep "." (lib.take 3 (lib.splitString "." address));
  tap = name: "vm-${builtins.substring 0 12 (builtins.hashString "sha256" name)}";

  # A Talos node gets an entropy device. A NixOS machine needs no seed drive, because its image holds its configuration.
  seedDrive = _vm: "-device virtio-rng-pci";

  # The disk of a VM is written once, from its image. A later start keeps the disk and the state on it.
  firstDisk =
    vm:
    {
      talos = ''
        zstd -q -d -o "$disk.new" ${cfg.images.talos}
        qemu-img resize -q -f raw "$disk.new" ${toString vm.disk}G
      '';
      nixos = ''
        cp --sparse=always ${vm.image} "$disk.new"
        chmod u+w "$disk.new"
        qemu-img resize -q -f raw "$disk.new" ${toString vm.disk}G
      '';
    }
    .${vm.kind};

  vmOptions =
    { name, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "The name of the VM.";
        };
        kind = mkOption {
          type = types.enum [
            "talos"
            "nixos"
          ];
          description = "The image that the VM starts from: a Talos node, or a NixOS machine such as the forge.";
        };
        image = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "The raw disk image of a NixOS machine. A Talos node starts from the shared Talos image.";
        };
        address = mkOption {
          type = types.str;
          description = "The private address of the VM.";
        };
        cores = mkOption {
          type = types.ints.positive;
          description = "The CPU cores of the VM.";
        };
        memory = mkOption {
          type = types.ints.positive;
          description = "The memory of the VM, in MiB.";
        };
        disk = mkOption {
          type = types.ints.positive;
          description = "The disk of the VM, in GiB.";
        };
      };
    };
in
{
  options.hypervisor = {
    vms = mkOption {
      type = types.attrsOf (types.submodule vmOptions);
      default = { };
      description = "The VMs that the host runs, by name.";
    };
    images.talos = mkOption {
      type = types.path;
      description = "The compressed raw Talos image that a new node starts from.";
    };
    uplink = mkOption {
      type = types.str;
      description = "The interface that leads to the internet.";
    };
    private = {
      gateway = mkOption {
        type = types.str;
        description = "The address of the host on the private bridge.";
      };
      prefix = mkOption {
        type = types.ints.between 8 30;
        description = "The prefix length of the private network.";
      };
      dhcpRange = mkOption {
        type = types.str;
        description = "The addresses that DHCP gives to a machine without a reservation.";
      };
      dns = mkOption {
        type = types.listOf types.str;
        description = "The DNS resolvers that DHCP announces.";
      };
    };
    public = {
      subnet = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The routed public subnet, with the address of the host in it.";
      };
      edge = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The public address of the cluster edge. Ports 80 and 443 reach Traefik on the first node.";
      };
      edgeTarget = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The node address that the edge forwards to.";
      };
      edgePorts = mkOption {
        type = types.attrsOf types.port;
        default = {
          http = 30080;
          https = 30443;
        };
        description = "The node ports that Traefik publishes.";
      };
      forge = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The public address of the forge. Ports 80, 443, and 2222 reach the forge VM.";
      };
      forgeTarget = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The private address of the forge VM.";
      };
      mail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The public address that outbound mail leaves from, per ADR-0307.";
      };
    };
  };

  config = {
    # The inventory of a provided fleet holds public addresses. A VM of this host gets a reservation only in the
    # private network.
    warnings =
      map
        (vm: "hypervisor: ${vm.name} has ${vm.address}, outside ${subnet}. DHCP gives it no reservation.")
        (
          lib.filter (vm: cfg.private.prefix != 24 || prefixOf vm.address != prefixOf cfg.private.gateway) vms
        );

    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.network.netdevs = {
      "20-private".netdevConfig = {
        Name = "private0";
        Kind = "bridge";
      };
    }
    // lib.optionalAttrs (cfg.public.subnet != null) {
      "20-public".netdevConfig = {
        Name = "public0";
        Kind = "bridge";
      };
    }
    // lib.listToAttrs (
      map (
        vm:
        lib.nameValuePair "21-${tap vm.name}" {
          netdevConfig = {
            Name = tap vm.name;
            Kind = "tap";
          };
        }
      ) vms
    );

    systemd.network.networks = {
      "20-private" = {
        matchConfig.Name = "private0";
        address = [ "${cfg.private.gateway}/${toString cfg.private.prefix}" ];
        networkConfig.ConfigureWithoutCarrier = true;
        linkConfig.RequiredForOnline = "no";
      };
    }
    // lib.optionalAttrs (cfg.public.subnet != null) {
      "20-public" = {
        matchConfig.Name = "public0";
        address = [ cfg.public.subnet ];
        networkConfig.ConfigureWithoutCarrier = true;
        linkConfig.RequiredForOnline = "no";
      };
    }
    // lib.listToAttrs (
      map (
        vm:
        lib.nameValuePair "21-${tap vm.name}" {
          matchConfig.Name = tap vm.name;
          networkConfig.Bridge = "private0";
          linkConfig.RequiredForOnline = "no";
        }
      ) vms
    );

    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = "private0";
        bind-interfaces = true;
        port = 0;
        dhcp-range = "${cfg.private.dhcpRange},12h";
        dhcp-option = [
          "option:router,${cfg.private.gateway}"
          "option:dns-server,${lib.concatStringsSep "," cfg.private.dns}"
        ];
        dhcp-host = map (vm: "${mac vm.address},${vm.name},${vm.address}") vms;
      };
    };

    # The VMs may take their time from the host.
    services.chrony = {
      enable = true;
      extraConfig = "allow ${subnet}";
    };
    networking.firewall.interfaces.private0.allowedUDPPorts = [
      67
      123
    ];

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernelModules = [ "vhost_net" ];
    networking.nftables.enable = true;
    networking.firewall.filterForward = true;
    networking.firewall.extraForwardRules = ''
      iifname "private0" accept
      ct status dnat accept
    '';

    # Each public address is a DNAT rule. The masquerade toward each target is the hairpin: a VM that reaches a public
    # address arrives with a private source, and without it the reply would skip the host.
    networking.nftables.tables.hypervisor-nat = {
      family = "ip";
      content =
        let
          dnat =
            public: target: pairs:
            lib.concatMapStrings (p: ''
              ip daddr ${public} tcp dport ${toString p.from} dnat to ${target}:${toString p.to}
            '') pairs;
          edge = lib.optionals (cfg.public.edge != null && cfg.public.edgeTarget != null) [
            {
              from = 80;
              to = cfg.public.edgePorts.http;
            }
            {
              from = 443;
              to = cfg.public.edgePorts.https;
            }
          ];
          forge = lib.optionals (cfg.public.forge != null && cfg.public.forgeTarget != null) (
            map
              (p: {
                from = p;
                to = p;
              })
              [
                80
                443
                2222
              ]
          );
          hairpin =
            target: pairs:
            lib.concatMapStrings (p: ''
              ip saddr ${subnet} ip daddr ${target} tcp dport ${toString p.to} masquerade
            '') pairs;
        in
        ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            ${lib.optionalString (edge != [ ]) (dnat cfg.public.edge cfg.public.edgeTarget edge)}
            ${lib.optionalString (forge != [ ]) (dnat cfg.public.forge cfg.public.forgeTarget forge)}
          }
          chain output {
            type nat hook output priority -100; policy accept;
            ${lib.optionalString (edge != [ ]) (dnat cfg.public.edge cfg.public.edgeTarget edge)}
            ${lib.optionalString (forge != [ ]) (dnat cfg.public.forge cfg.public.forgeTarget forge)}
          }
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ${lib.optionalString (edge != [ ]) (hairpin cfg.public.edgeTarget edge)}
            ${lib.optionalString (forge != [ ]) (hairpin cfg.public.forgeTarget forge)}
            ${lib.optionalString (
              cfg.public.mail != null
            ) "ip saddr ${subnet} tcp dport 25 oifname \"${cfg.uplink}\" snat to ${cfg.public.mail}"}
            ip saddr ${subnet} ip daddr != ${subnet} oifname "${cfg.uplink}" masquerade
          }
        '';
    };

    systemd.services = lib.listToAttrs (
      map (
        vm:
        lib.nameValuePair "vm-${vm.name}" {
          description = "The VM ${vm.name}";
          wantedBy = [ "multi-user.target" ];
          after = [
            "systemd-networkd.service"
            "dnsmasq.service"
          ];
          path = [
            pkgs.zstd
            pkgs.qemu_kvm
          ];
          serviceConfig = {
            StateDirectory = "vms";
            Restart = "always";
            RestartSec = 5;
          };
          preStart = ''
            disk=/var/lib/vms/${vm.name}.raw
            if [ ! -e "$disk" ]; then
              rm -f "$disk.new"
              ${firstDisk vm}
              mv "$disk.new" "$disk"
            fi
          '';
          script = ''
            exec qemu-system-x86_64 \
              -name ${vm.name} -machine q35,accel=kvm -cpu host \
              -smp ${toString vm.cores} -m ${toString vm.memory} \
              -nographic -monitor none -serial file:/var/lib/vms/${vm.name}.console \
              -device virtio-scsi-pci,id=scsi0 \
              -drive file=/var/lib/vms/${vm.name}.raw,if=none,id=disk0,format=raw,cache=none,aio=native \
              -device scsi-hd,drive=disk0,bus=scsi0.0 \
              ${seedDrive vm} \
              -netdev tap,id=net0,ifname=${tap vm.name},script=no,downscript=no,vhost=on \
              -device virtio-net-pci,netdev=net0,mac=${mac vm.address}
          '';
        }
      ) vms
    );
  };
}
