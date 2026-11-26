# The CI runner machine, per ADR-0116: NixOS with Docker and forgejo-runner. It is never the forge and never a
# cluster node, because a job controls the Docker of this machine, and that is root on it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  settings = import ./settings.nix;
  forge = import ../forge-host/settings.nix;
  names = map toString (lib.range 1 settings.instances);
  home = n: "/var/lib/gitea-runner/${n}";
  # `just runner-token` writes the registration token here. It never enters the Nix store.
  tokenFile = "/var/lib/forgejo-runner/token";
  labels = [
    "ubuntu-24.04:host"
    "ubuntu-latest:host"
  ];
  # What a provider-hosted image carries and a job assumes: Node for JavaScript actions, and Docker for kind and images.
  tools = with pkgs; [
    bash
    coreutils
    curl
    findutils
    gawk
    gitMinimal
    git-lfs
    gnugrep
    gnupg
    gnused
    gnutar
    gzip
    jq
    nodejs
    unzip
    xz
    zstd
    docker
    config.nix.package
  ];

  # A job that dies before its post steps leaves its BuildKit builder or its kind cluster running. Nothing else on a
  # machine that outlives its jobs removes them. Anything younger than the job cap is left, because a live job can use it.
  gc = pkgs.writeShellApplication {
    name = "runner-gc";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      findutils
      procps
    ];
    text = ''
      cutoff=$(date -d '-3 hours' +%s)
      old() { [ "$(date -d "$(docker inspect -f '{{.Created}}' "$1")" +%s)" -lt "$cutoff" ]; }
      # A `ci-keep-` builder is the cache that ci-build-images keeps between jobs on purpose, and BuildKit's own GC bounds it.
      docker ps -a --filter name=buildx_buildkit_ --format '{{.Names}}' | while read -r c; do
        case "$c" in buildx_buildkit_ci-keep-*) continue ;; esac
        old "$c" || continue
        docker rm -f "$c" >/dev/null && docker volume rm "''${c}_state" >/dev/null 2>&1 || true
      done
      # An orphaned kind node or job registry also holds the ports and the lock that every later job needs.
      for label in io.x-k8s.kind.cluster platform.ci-job; do
        docker ps -a --filter "label=$label" --format '{{.Names}}' | while read -r c; do
          if old "$c"; then docker rm -f -v "$c" >/dev/null; fi
        done
      done
      docker volume prune -f >/dev/null
      # A job's zot store gathers the first-party images of every commit. Past 20GB, and with no registry serving it,
      # it goes. The next job restores the third-party mirror from the Actions cache.
      if [ -z "$(docker ps -q --filter name=registry.localhost)" ]; then
        for d in /var/lib/gitea-runner/*/.cache/zot/*; do
          if [ -d "$d" ] && [ "$(du -s "$d" | cut -f1)" -gt 20000000 ]; then rm -rf "$d"; fi
        done
      fi
      # Go trims only entries unused for five days, so the build cache of a busy runner grows past the kubelet's disk
      # threshold, and kind evicts pods. Past 15GB, and with no go process running, it goes.
      if ! pgrep -x go >/dev/null; then
        for d in /var/lib/gitea-runner/*/.cache/go-build; do
          if [ -d "$d" ] && [ "$(du -s "$d" | cut -f1)" -gt 15000000 ]; then rm -rf "$d"; fi
        done
      fi
      docker image prune -af --filter until=6h >/dev/null
      docker builder prune -af --filter until=6h >/dev/null
    '';
  };
in
{
  imports = [ ../forge-host/machine.nix ];

  networking.hostName = "runner";

  virtualisation.docker.enable = true;
  # kind runs a kubelet in each node container. Each one holds inotify instances, and the default runs out.
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };
  # Every checkout runs `git init`, which prints a hint on each job while git has no default branch name.
  programs.git = {
    enable = true;
    lfs.enable = true;
    config.init.defaultBranch = "master";
  };
  environment.systemPackages = tools;

  # One job per instance, each with its own home, temp directory, and Actions cache. Tools unpack into both, and one
  # job's cache restore or registry logout otherwise lands under another job that is still running.
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances = lib.genAttrs names (n: {
      enable = true;
      name = "runner-${n}";
      url = lib.mkDefault "https://${forge.domain}";
      inherit tokenFile labels;
      hostPackages = tools;
      settings = {
        runner = {
          capacity = 1;
          # Above every workflow's timeout-minutes, which is the limit that ends a job.
          timeout = "3h";
          envs = {
            PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
            XDG_RUNTIME_DIR = "${home n}/run";
            TMPDIR = "${home n}/tmp";
          };
        };
        cache = {
          enabled = true;
          dir = "${home n}/cache";
          host = settings.address;
          port = 40010 + lib.toInt n;
        };
        host.workdir_parent = "${home n}/work";
      };
    });
  };
  # `ubuntu-24.04` is the machine itself, as on a provider-hosted runner, so a job runs Docker directly.
  systemd.services =
    lib.listToAttrs (
      map (n: {
        name = "gitea-runner-${n}";
        value = {
          unitConfig.ConditionPathExists = tokenFile;
          serviceConfig = {
            EnvironmentFile = lib.mkForce [
              tokenFile
              "-/etc/platform/proxy.env"
            ];
            SupplementaryGroups = lib.mkForce [ "docker" ];
            ExecStartPre = lib.mkAfter [
              "${pkgs.coreutils}/bin/mkdir -p ${home n}/run ${home n}/tmp ${home n}/work"
            ];
          };
        };
      }) names
    )
    // {
      docker.serviceConfig.EnvironmentFile = "-/etc/platform/proxy.env";
      runner-gc = {
        description = "Reclaim what finished CI jobs left behind";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe gc;
        };
      };
    };
  systemd.timers.runner-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
  # BuildKit reaches the Actions cache on the address of the machine, from its own container.
  networking.firewall.allowedTCPPorts =
    map (n: 40010 + lib.toInt n) names ++ lib.optional settings.probe.enable settings.probe.port;

  # The registry probe of ADR-0500. The password hash is not a secret, so it may enter the store.
  services.prometheus.exporters.blackbox = lib.mkIf settings.probe.enable {
    enable = true;
    listenAddress = settings.address;
    inherit (settings.probe) port;
    configFile = pkgs.writeText "blackbox.yml" (
      builtins.toJSON {
        modules.registry_https = {
          prober = "http";
          timeout = "10s";
          http = {
            method = "GET";
            fail_if_not_ssl = true;
            preferred_ip_protocol = "ip4";
            # An authenticated registry answers 401 to a request with no credential.
            valid_status_codes = [
              200
              401
            ];
          };
        };
      }
    );
    extraFlags = [
      "--web.config.file=${
        pkgs.writeText "blackbox-web.yml" (
          builtins.toJSON { basic_auth_users.otel-cluster = settings.probe.passwordHash; }
        )
      }"
    ];
  };
  assertions = [
    {
      assertion = !settings.probe.enable || settings.probe.passwordHash != null;
      message = "infra/runner/settings.nix: set probe.passwordHash to the bcrypt hash of the probe password";
    }
  ];
}
