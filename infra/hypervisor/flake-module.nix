# The hypervisor mode, per ADR-0208: the host, its deploy, and its QEMU copy. flake.nix loads this file only when it
# exists, so a project in another provisioning mode has none of it.
{
  inputs,
  lib,
  ...
}:
let
  system = "x86_64-linux";
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  settings = import ./settings.nix;
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;

  host =
    settings: extra:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit settings; };
      modules = [
        inputs.tabnix.nixosModules.server
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
        memory = 2048;
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
    imports = [ "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
  };
in
{
  imports = [ inputs.tabnix.flakeModules.deploy ];

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
  tabnix.deploy.nodes = {
    hypervisor.hostname = settings.address;
  }
  // lib.genAttrs [ "hypervisor-lab" "hypervisor-lab-broken" "hypervisor-lab-next" ] (_: {
    hostname = "127.0.0.1";
    confirmTimeout = 60;
  });

  perSystem =
    { pkgs, system, ... }:
    {
      tabnix.packages = [
        inputs.tabnix.inputs.deploy-rs.packages.${system}.default
        pkgs.nixos-anywhere
        pkgs.qemu_kvm
      ];
      packages = lib.optionalAttrs (system == "x86_64-linux") {
        # The installer of the QEMU copy, and the private test key that logs in to it.
        hypervisor-lab-installer =
          (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              {
                users.users.root.openssh.authorizedKeys.keys = [ keys.snakeOilEd25519PublicKey ];
                isoImage.squashfsCompression = "zstd -Xcompression-level 3";
              }
            ];
          }).config.system.build.isoImage;
        hypervisor-lab-key = keys.snakeOilEd25519PrivateKey;
      };
    };
}
