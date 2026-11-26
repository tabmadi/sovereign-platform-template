# The forge mode, per ADR-0116: the forge and the runner as NixOS machines, their deploy, their disk images, and a test
# that boots both. flake.nix loads this file only when it exists, so a project on another forge has none of it.
{ inputs, lib, ... }:
let
  guest = import ./guest.nix { inherit inputs; };
  forge = import ./settings.nix;
  runner = import ../runner/settings.nix;
  # A machine on a private network is reached through its jump host.
  through = jump: lib.optionals (jump != null) [ "-J ${jump}" ];
  pkgs = inputs.nixos.legacyPackages.x86_64-linux;
in
{
  flake.nixosConfigurations = {
    forge = guest.machine "forge" { };
    runner = guest.machine "runner" { };
  };

  # A deploy that loses SSH rolls back by itself, per ADR-0500 of tabkit.
  tabkit.deploy.nodes = {
    forge = {
      hostname = forge.address;
      sshOpts = through forge.jump;
    };
    runner = {
      hostname = runner.address;
      sshOpts = through runner.jump;
    };
  };

  perSystem =
    { system, ... }:
    {
      tabkit.packages = [ inputs.tabkit.inputs.deploy-rs.packages.${system}.default ];
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      # The disk that a new VM starts from, where no hypervisor of this repo runs it.
      packages = {
        forge-image = pkgs.runCommand "forge.img" { } "ln -s ${guest.image "forge" { }} $out";
        runner-image = pkgs.runCommand "runner.img" { } "ln -s ${guest.image "runner" { }} $out";
      };
      # Both machines boot, and the runner registers with the forge, with no internet and no ACME.
      checks.forge-runner = pkgs.testers.runNixOSTest (import ./test.nix { inherit inputs; });
    };
}
