# The forge machine, per ADR-0116: NixOS with Forgejo and its Postgres, on the server base of tabkit.
# A forge that Argo CD deployed could not recover a lost cluster, so it is a machine beside the cluster, never a chart.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  settings = import ./settings.nix;
  # The slug of infra/project.yaml names the forge, so this file repeats no project name.
  slug = lib.removePrefix "slug: " (
    lib.findFirst (line: lib.hasPrefix "slug: " line) "slug: platform" (
      lib.splitString "\n" (builtins.readFile ../project.yaml)
    )
  );
  signed = settings.signing.key != null;
in
{
  imports = [ ./machine.nix ];

  networking.hostName = "forge";

  services.forgejo = {
    enable = true;
    # Peer authentication over the local socket, so the database has no password to keep.
    database = {
      type = "postgres";
      createDatabase = true;
    };
    lfs.enable = true;
    settings = {
      DEFAULT.APP_NAME = slug;
      # The own ACME client of Forgejo, not a reverse proxy. The machine serves one service on 80 and 443.
      server = {
        PROTOCOL = "https";
        DOMAIN = settings.domain;
        ROOT_URL = "https://${settings.domain}/";
        HTTP_PORT = 443;
        REDIRECT_OTHER_PORT = true;
        PORT_TO_REDIRECT = 80;
        ENABLE_ACME = true;
        ACME_ACCEPTTOS = true;
        ACME_DIRECTORY = "/var/lib/forgejo/acme";
        ACME_EMAIL = settings.acmeEmail;
        START_SSH_SERVER = true;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
      };
      service.DISABLE_REGISTRATION = true;
      repository.DEFAULT_BRANCH = "master";
      # The forge signs the squash commit of every merge. MERGES = always is needed, because the default also asks
      # that the commits of the branch are signed, and a contributor has no key.
      "repository.signing" = lib.mkIf signed {
        SIGNING_KEY = settings.signing.key;
        SIGNING_NAME = settings.signing.name;
        SIGNING_EMAIL = settings.signing.email;
        MERGES = "always";
      };
      actions = {
        ENABLED = true;
        # The workflows call actions from GitHub that the default action mirror does not carry.
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };
  # `just forge-signing` imports the key here. It never enters the Nix store.
  systemd.services.forgejo.environment.GNUPGHOME = "${config.services.forgejo.stateDir}/.gnupg";

  # Forgejo binds 80 and 443 itself. The sandbox of the unit drops every capability, so the kernel allows the ports.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;
  networking.firewall.allowedTCPPorts = [
    80
    443
    2222
  ];

  # The admin commands of forge.sh run the same Forgejo as the service.
  environment.systemPackages = [ config.services.forgejo.package ];
}
