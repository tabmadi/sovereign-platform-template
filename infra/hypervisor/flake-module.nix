# The hypervisor mode, per ADR-0208: the host, its deploy, and its QEMU copy. flake.nix loads this file only when it
# exists, so a project in another provisioning mode has none of it.
{
  inputs,
  lib,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = inputs.nixos.legacyPackages.${system};
  settings = import ./settings.nix;
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  # The forge kit builds the forge and the runner. A project without it reads none of this.
  guest = import ../forge-host/guest.nix { inherit inputs; };

  host =
    settings: extra:
    inputs.nixos.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit settings;
        # The forge and the runner boot from their own NixOS image, with the admin keys of this host.
        guestImages = lib.genAttrs [ "forge" "runner" ] (
          name: guest.image name { tabkit.server.adminKeys = lib.mkForce settings.adminKeys; }
        );
      };
      modules = [
        inputs.tabkit.nixosModules.server
        inputs.disko.nixosModules.disko
        ./disk.nix
        ./host.nix
        extra
      ];
    };

  # The QEMU copy: one virtual disk, small VMs, and the public test key of nixpkgs. It listens only on a port of the
  # laptop, so the test key reaches nothing else.
  lab = settings // {
    hostName = "hypervisor-lab";
    hostMetrics.enable = true;
    disk = "/dev/vda";
    adminKeys = [ keys.snakeOilEd25519PublicKey ];
    uplink = {
      interface = "eth0";
      address = null;
      gateway = null;
    };
    nodes = {
      lab-cp-1.address = "10.0.10.11";
      lab-cp-2.address = "10.0.10.12";
      lab-cp-3.address = "10.0.10.13";
    };
    sizes = {
      node = {
        cores = 2;
        memory = 3072;
        disk = 10;
      };
      forge = {
        cores = 1;
        memory = 1024;
        disk = 8;
      };
      runner = {
        cores = 1;
        memory = 1024;
        disk = 8;
      };
    };
  };
  labExtra = {
    imports = [ "${inputs.nixos}/nixos/modules/profiles/qemu-guest.nix" ];
    # The host serves its own clock to the nodes, so the offline lab needs no public time server.
    services.chrony.extraConfig = lib.mkAfter "local stratum 10";
  };
in
{
  imports = [ inputs.tabkit.flakeModules.full-tier ];

  # The QEMU copy on one disk. lab.sh adds the registry forward and the offline network at run time.
  tabkit.fullTier.lab = {
    configuration = "hypervisor-lab";
    node = "hypervisor-lab";
    cpus = 8;
    memory = 14336;
    diskSize = 80;
    disks = 1;
    minFreeMemory = 16;
    minFreeDisk = 20;
    sshPort = 2222;
    adminKeys = [ keys.snakeOilEd25519PublicKey ];
  };

  flake.nixosConfigurations = {
    hypervisor = host settings { };
    hypervisor-lab = host lab labExtra;
    # The firewall closes SSH, so a deploy of it must roll back by itself.
    hypervisor-lab-broken = host lab {
      imports = [ labExtra ];
      services.openssh.openFirewall = lib.mkForce false;
    };
    # A change that takes effect only at the next boot.
    hypervisor-lab-next = host lab {
      imports = [ labExtra ];
      environment.etc."lab-generation".text = "next";
    };
  };

  # A deploy that loses SSH rolls back by itself, per ADR-0208.
  tabkit.deploy.nodes = {
    hypervisor.hostname = settings.address;
  }
  # The QEMU copies deploy only in `just hypervisor-test`. The real host proves the same modules in the checks.
  // lib.genAttrs [ "hypervisor-lab" "hypervisor-lab-broken" "hypervisor-lab-next" ] (_: {
    hostname = "127.0.0.1";
    confirmTimeout = 60;
    check = false;
  });

  perSystem =
    { pkgs, system, ... }:
    {
      tabkit.packages = [
        inputs.tabkit.inputs.deploy-rs.packages.${system}.default
        pkgs.nixos-anywhere
        pkgs.qemu_kvm
        pkgs.skopeo
        pkgs.socat
      ];
      packages = lib.optionalAttrs (system == "x86_64-linux") {
        # The private test key that logs in to the QEMU copy.
        hypervisor-lab-key = keys.snakeOilEd25519PrivateKey;
      };
    };
}
