# The test of the forge mode, per ADR-0116. The forge serves plain HTTP on 3000 in place of its public name, and the
# runner registers with a token that the forge mints, as `just runner-token` does.
{ inputs }:
{ lib, ... }:
let
  testKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOhrqYkKdbuPJu3HPN3x0mxAhxy4X4MzCKmYq2gWWkYr test";
in
{
  name = "forge-runner";
  defaults = {
    imports = [ inputs.tabkit.nixosModules.server ];
    tabkit.server.adminKeys = lib.mkForce [ testKey ];
    virtualisation.memorySize = 2048;
  };
  nodes = {
    forge = {
      imports = [ ./forge.nix ];
      services.forgejo.settings.server = {
        PROTOCOL = lib.mkForce "http";
        DOMAIN = lib.mkForce "forge";
        HTTP_PORT = lib.mkForce 3000;
        ROOT_URL = lib.mkForce "http://forge:3000/";
        ENABLE_ACME = lib.mkForce false;
        REDIRECT_OTHER_PORT = lib.mkForce false;
      };
      networking.firewall.allowedTCPPorts = [ 3000 ];
    };
    runner = {
      imports = [ ../runner/runner.nix ];
      services.gitea-actions-runner.instances."1".url = lib.mkForce "http://forge:3000";
    };
  };
  testScript = ''
    start_all()
    forge.wait_for_unit("forgejo.service")
    forge.wait_for_open_port(3000)
    forge.wait_for_open_port(2222)

    # The runner unit waits for its token, so a fresh machine starts no runner.
    runner.wait_for_unit("docker.service")
    runner.fail("systemctl is-active gitea-runner-1")

    token = forge.succeed(
        "runuser -u forgejo -- forgejo --work-path /var/lib/forgejo actions generate-runner-token"
    ).strip().splitlines()[-1]
    runner.succeed(f"install -d -m 0700 /var/lib/forgejo-runner && echo TOKEN={token} > /var/lib/forgejo-runner/token")
    runner.succeed("systemctl start gitea-runner-1")
    forge.wait_until_succeeds(
        "runuser -u postgres -- psql -d forgejo -tAc 'select count(*) from action_runner' | grep -qx 1",
        timeout=180,
    )
    runner.succeed("systemctl is-active gitea-runner-1")
    # A job runs Docker directly.
    runner.succeed("systemctl show gitea-runner-1 -p SupplementaryGroups | grep -q docker")
    runner.succeed("systemctl list-timers runner-gc.timer | grep -q runner-gc")

    runner.succeed("install -d -m 0700 /etc/platform")
    runner.succeed("printf 'NO_PROXY=forge,internal.example\n' > /etc/platform/proxy.env")
    runner.succeed("systemctl restart gitea-runner-1 docker")
    runner.wait_for_unit("gitea-runner-1.service")
    runner.succeed("docker info --format '{{.NoProxy}}' | grep -qx forge,internal.example")
    runner.succeed(
        "pid=$(systemctl show gitea-runner-1 -p MainPID --value); "
        "tr '\\0' '\\n' < /proc/$pid/environ | grep -qx NO_PROXY=forge,internal.example"
    )
  '';
}
