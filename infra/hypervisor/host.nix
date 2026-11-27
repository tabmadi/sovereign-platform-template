# The hypervisor host, per ADR-0208: NixOS on the machine that the project owns. It runs the Talos nodes of the
# inventory, and the forge and the runner when their kits exist, as VMs on one private bridge.
{
  lib,
  pkgs,
  modulesPath,
  settings,
  guestImages,
  ...
}:
let
  # The inventory is YAML, so it becomes JSON once at evaluation.
  inventory = lib.importJSON (
    pkgs.runCommand "inventory.json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
      yq -o json ${../talos/inventory + "/${settings.environment}/nodes.yml"} > $out
    ''
  );

  forgeSettings = ../forge-host/settings.nix;
  runnerSettings = ../runner/settings.nix;
  forgeAddress = (import forgeSettings).address;

  # A QEMU copy of the host names its own nodes. A real host takes them from the inventory.
  nodes = lib.mapAttrs (_: node: {
    kind = "talos";
    inherit (node) address;
    inherit (settings.sizes.node) cores memory disk;
  }) (settings.nodes or inventory.nodes);

  guests =
    lib.optionalAttrs (builtins.pathExists forgeSettings) {
      forge = {
        kind = "nixos";
        image = guestImages.forge;
        address = forgeAddress;
        inherit (settings.sizes.forge) cores memory disk;
      };
    }
    // lib.optionalAttrs (builtins.pathExists runnerSettings) {
      runner = {
        kind = "nixos";
        image = guestImages.runner;
        address = (import runnerSettings).address;
        inherit (settings.sizes.runner) cores memory disk;
      };
    };
in
{
  imports = [
    "${modulesPath}/installer/scan/not-detected.nix"
    ./vms.nix
  ];

  system.stateVersion = "26.05";

  networking.hostName = settings.hostName;
  time.timeZone = "UTC";

  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];

  tabkit.server = {
    enable = true;
    inherit (settings) adminKeys;
  };

  # The first network interface is eth0 on every machine.
  networking.usePredictableInterfaceNames = false;
  systemd.network.networks."10-uplink" = {
    matchConfig.Name = settings.uplink.interface;
    linkConfig.RequiredForOnline = "routable";
  }
  // (
    if settings.uplink.address == null then
      { networkConfig.DHCP = "yes"; }
    else
      {
        address = [ settings.uplink.address ];
        routes = [
          {
            Gateway = settings.uplink.gateway;
            GatewayOnLink = true;
          }
        ];
      }
  );

  hypervisor = {
    vms = nodes // guests;
    images.talos = pkgs.fetchurl { inherit (settings.talos) url hash; };
    uplink = settings.uplink.interface;
    inherit (settings) private;
    public = {
      inherit (settings.public)
        subnet
        edge
        forge
        mail
        ;
      edgeTarget = (lib.head (lib.attrValues nodes)).address;
      forgeTarget = if guests ? forge then forgeAddress else null;
      inherit (settings) edgePorts;
    };
  };

  environment.systemPackages = [ pkgs.talosctl ];

  # Host pressure and disk latency, per ADR-0208. The exporter binds the bridge address, so the uplink never serves it.
  services.prometheus.exporters.node = lib.mkIf (settings.hostMetrics.enable or false) {
    enable = true;
    listenAddress = settings.private.gateway;
    port = 9100;
    enabledCollectors = [ "pressure" ];
  };
  systemd.services.prometheus-node-exporter = lib.mkIf (settings.hostMetrics.enable or false) {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
  networking.firewall.interfaces.private0.allowedTCPPorts = lib.mkIf (settings.hostMetrics.enable
    or false
  ) [ 9100 ];
}
