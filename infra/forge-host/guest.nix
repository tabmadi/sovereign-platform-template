# The NixOS machines beside the cluster, per ADR-0116: the forge and the runner. The forge kit and the hypervisor both
# build them here, so a VM image and a deploy run the same configuration.
{ inputs }:
let
  modules = {
    forge = ./forge.nix;
    runner = ../runner/runner.nix;
  };
in
rec {
  # One machine. `extra` is a module, such as the admin keys of the QEMU copy of the hypervisor.
  machine =
    name: extra:
    inputs.nixos.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.tabkit.nixosModules.server
        inputs.tabkit.nixosModules.egress
        ../egress.nix
        modules.${name}
        extra
      ];
    };
  # The raw disk that a new VM of the machine starts from.
  image = name: extra: imageOf (machine name extra);
  imageOf = system: "${system.config.system.build.image}/${system.config.image.filePath}";
  # The same disk as compressed qcow2, for the hypervisor. A raw image stores its empty space, so the closure of the
  # host would carry about 10 GiB more, and every install or deploy of the host would copy it.
  compressedImage =
    name: extra:
    let
      pkgs = inputs.nixos.legacyPackages.x86_64-linux;
    in
    pkgs.runCommand "${name}.qcow2" { nativeBuildInputs = [ pkgs.qemu-utils ]; } ''
      qemu-img convert -c -f raw -O qcow2 ${image name extra} $out
    '';
}
