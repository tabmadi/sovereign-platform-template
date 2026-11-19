# The hypervisor host, per ADR-0208: NixOS on the machine that the project owns. It runs the Talos nodes of the
# inventory, and the forge and the runner when their kits exist, as VMs on one private bridge.
{
  lib,
  pkgs,
  modulesPath,
  settings,
  ...
}:
let
  # The inventory is YAML, so it becomes JSON once at evaluation.
  inventory = lib.importJSON (
    pkgs.runCommand "inventory.json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
      yq -o json ${../talos/inventory + "/${settings.environment}/nodes.yml"} > $out
    ''
  );

  # One value of a KEY=value file, such as forge.env.
  envValue =
    file: key:
    let
      line = lib.findFirst (l: lib.hasPrefix "${key}=" l) "" (
        lib.splitString "\n" (builtins.readFile file)
      );
    in
    lib.removePrefix "${key}=" line;

  forgeEnv = ../forge-host/forge.env;
  runnerEnv = ../runner/runner.env;
  forgeAddress = lib.last (lib.splitString "@" (envValue forgeEnv "FORGE_SSH"));

  # A QEMU copy of the host names its own nodes. A real host takes them from the inventory.
  nodes = lib.mapAttrs (_: node: {
    kind = "talos";
    inherit (node) address;
    inherit (settings.sizes.node) cores memory disk;
  }) (settings.nodes or inventory.nodes);

  guests =
    lib.optionalAttrs (builtins.pathExists forgeEnv) {
      forge = {
        kind = "debian";
        address = forgeAddress;
        inherit (settings.sizes.forge) cores memory disk;
      };
    }
    // lib.optionalAttrs (builtins.pathExists runnerEnv) {
      runner = {
        kind = "debian";
        address = envValue runnerEnv "RUNNER_ADDRESS";
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

  tabnix.server = {
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
    images = {
      talos = pkgs.fetchurl { inherit (settings.talos) url hash; };
      debian = pkgs.fetchurl { inherit (settings.debian) url hash; };
    };
    inherit (settings) adminKeys;
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
}
