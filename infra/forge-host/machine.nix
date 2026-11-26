# The base of the forge and the runner, per ADR-0116: a NixOS VM on the server base of tabkit.
# Each one boots from the disk image of its own configuration, and a deploy-rs deploy changes it after that.
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    "${modulesPath}/virtualisation/disk-image.nix"
  ];

  system.stateVersion = "26.05";

  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "-/etc/platform/proxy.env";

  tabkit.server = {
    enable = true;
    adminKeys = lib.mkDefault (import ./settings.nix).adminKeys;
  };

  # The hypervisor starts each VM with BIOS and its disk on virtio-scsi, so the disk is /dev/sda.
  image = {
    format = "raw";
    efiSupport = false;
  };
  boot.loader.grub.devices = lib.mkForce [ "/dev/sda" ];
  boot.initrd.availableKernelModules = [
    "virtio_scsi"
    "sd_mod"
  ];

  # The hypervisor gives each VM the address that its MAC names, over DHCP.
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = true;
}
