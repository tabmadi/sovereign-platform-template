# The facts of the CI runner machine, per ADR-0116. None is a secret. runner.nix, the hypervisor, and runner.sh read them.
{
  # The private address of the machine. BuildKit reaches the Actions cache on it from its own container, so loopback fails.
  address = "10.0.10.40";
  # Null when a workstation reaches the runner directly. On a private network, the host that reaches it, as `user@host`.
  jump = "root@198.51.100.2";

  # One job at a time. A machine has one registry port and one set of edge ports, so a second job that starts a
  # cluster waits for the first, per ADR-0116.
  instances = 1;

  # The blackbox exporter of ADR-0500 on the private address of this machine.
  probe = {
    enable = false;
    port = 9115;
    # The bcrypt hash of the password of `otel-cluster`. A hash is not a secret.
    passwordHash = null;
  };
}
