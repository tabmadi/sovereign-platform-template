# The facts of the hypervisor host, per ADR-0208. None is a secret. The node names and addresses are in
# infra/talos/inventory/<environment>/nodes.yml, and the forge and runner addresses are in their own .env files.
{
  hostName = "hypervisor";
  # The inventory whose nodes run here.
  environment = "dev";
  # The address that the deploy and the install connect to.
  address = "198.51.100.2";
  # The disk that the install erases, by its stable name in /dev/disk/by-id.
  disk = "/dev/disk/by-id/REPLACE-WITH-THE-DISK-ID";
  # The SSH public keys that log in as root.
  adminKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithTheKeyOfTheOwner owner" ];

  # The uplink. A null address takes DHCP, which suits most rented servers that announce one.
  uplink = {
    interface = "eth0";
    address = null;
    gateway = null;
  };

  # The routed public subnet. Each public address is a NAT rule, not an address of a VM. A null value skips the rule.
  public = {
    subnet = "198.51.100.97/29";
    edge = "198.51.100.101";
    forge = "198.51.100.99";
    mail = "198.51.100.98";
  };
  # The node ports that Traefik publishes, per ADR-0305.
  edgePorts = {
    http = 30080;
    https = 30443;
  };

  # Run a node exporter on the private bridge for the Registry health dashboard, per ADR-0208.
  hostMetrics.enable = false;

  # The private network of every node and VM. It reaches the internet through NAT on the host.
  private = {
    gateway = "10.0.10.1";
    prefix = 24;
    dhcpRange = "10.0.10.100,10.0.10.200";
    dns = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };

  # Sizes, in cores, MiB of memory, and GiB of disk. A project sets them from its own measurement, per ADR-0204.
  sizes = {
    node = {
      cores = 4;
      memory = 8192;
      disk = 60;
    };
    forge = {
      cores = 2;
      memory = 4096;
      disk = 40;
    };
    runner = {
      cores = 4;
      memory = 16384;
      disk = 160;
    };
  };

  # The images that a new VM starts from. The Talos image comes from the Image Factory schematic of infra/talos/.
  talos = {
    url = "https://factory.talos.dev/image/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245/v1.14.6/metal-amd64.raw.zst";
    hash = "sha256-aNdZSxPFPpoi9Dvr1Obkk3jELRFH/Mq1cfeuwLM2IQA=";
  };
  debian = {
    url = "https://cloud.debian.org/images/cloud/trixie/20261116-2664/debian-13-genericcloud-amd64-20261116-2664.qcow2";
    hash = "sha256-7dKz+53ovFGyn/hCVxYYDI9jHyP2sH+eKIpXvRhwERY=";
  };
}
