# The disk of the host, per ADR-0208. disko erases and partitions it when nixos-anywhere installs the host. The disk
# boots by BIOS and by UEFI, so one layout fits most servers.
{ settings, ... }:
{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  disko.devices.disk.main = {
    type = "disk";
    device = settings.disk;
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
