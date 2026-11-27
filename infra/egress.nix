# The egress of the forge, the runner, and the hypervisor, per the egress ADR of tabkit. Every machine of this repo imports it.
# Follow docs/egress.md to choose the level and the mirrors for a site.
{
  tabkit.egress = {
    enable = true;
    # One of direct, proxy, internal, or airgap.
    level = "direct";
    # The proxy URL at the proxy level, without credentials. A URL with credentials goes into `environmentFile`.
    proxy = null;
    # The names and ranges of the site that each machine reaches directly.
    noProxy = [ ];
    # The internal Nix caches and their keys. At internal and airgap, they are the only substituters.
    substituters = [ ];
    trustedPublicKeys = [ ];
    # The registry that mirrors each upstream under a path of its host name.
    registryMirror = null;
  };
}
