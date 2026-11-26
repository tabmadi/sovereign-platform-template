# The toolchain, the git hooks, the island shells, and the checks, per ADR-0100 and ADR-0111.
# The tabkit module holds every shared part, and this file adds the parts of the platform.
{
  description = "A self-hosted platform monorepo, with every reusable decision recorded as an ADR and enforced in CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # The machines of the hypervisor mode build from the stable release, per ADR-0100.
    nixos.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # A new version is a new tag here.
    tabkit = {
      url = "github:tabmadi/tabkit/v0.26.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixos-stable.follows = "nixos";
    };
    # The disk layout of the hypervisor mode, per ADR-0208. A project in another mode never fetches it.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, tabkit, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # The template scope adds its own checks and outputs. A copy has no template/ folder, so it adds nothing.
      # The bun module of tabkit holds Bun, bun2nix, the hook for bun.nix, and the install and check helpers.
      imports = [
        tabkit.flakeModules.default
        tabkit.flakeModules.bun
        tabkit.flakeModules.go
        tabkit.flakeModules.shell
      ]
      ++ inputs.nixpkgs.lib.optional (builtins.pathExists ./template/scope.nix) ./template/scope.nix
      # The machines of the hypervisor mode and of the forge mode deploy with deploy-rs, per ADR-0208 and ADR-0116.
      ++ inputs.nixpkgs.lib.optional (
        builtins.pathExists ./infra/hypervisor/flake-module.nix
        || builtins.pathExists ./infra/forge-host/flake-module.nix
      ) tabkit.flakeModules.deploy
      # The hypervisor mode of ADR-0208 adds the host and its QEMU copy.
      ++ inputs.nixpkgs.lib.optional (builtins.pathExists ./infra/hypervisor/flake-module.nix) ./infra/hypervisor/flake-module.nix
      # The forge mode of ADR-0116 adds the forge, the runner, their images, and their test.
      ++ inputs.nixpkgs.lib.optional (builtins.pathExists ./infra/forge-host/flake-module.nix) ./infra/forge-host/flake-module.nix;

      perSystem =
        {
          config,
          lib,
          system,
          ...
        }:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};

          inherit (config.tabkit.bun) check;

          # cosign stays on 2.x, per ADR-0113: cosign 3 writes only the Sigstore bundle format,
          # and Kyverno verifies that format through the public TUF root, which ADR-0113 rejects.
          # The release binary of sigstore, not a build from source: a build takes minutes in each CI job, and the
          # public Nix cache has only cosign 3. The hashes match the cosign_checksums.txt of the release.
          cosign =
            let
              arch =
                {
                  x86_64-linux = "amd64";
                  aarch64-linux = "arm64";
                }
                .${system};
              hash =
                {
                  amd64 = "sha256-w7T1QQ5givA6XrCqrISkMT2NoTEkjgj/F1mscMedFkQ=";
                  arm64 = "sha256-QmGTtMXaTU1kPoIvSP4MyKR2yheConJwSDH1oM73Ftc=";
                }
                .${arch};
            in
            pkgs.runCommand "cosign-2.6.5" { meta.mainProgram = "cosign"; } ''
              install -Dm755 ${
                pkgs.fetchurl {
                  url = "https://github.com/sigstore/cosign/releases/download/v2.6.5/cosign-linux-${arch}";
                  inherit hash;
                }
              } $out/bin/cosign
            '';
          go = pkgs.go;

          # Every Go module that the workspace and its tools need, as a module proxy. The hash pins the download.
          # A change to a go.mod or go.sum changes the hash: run `just nix-hashes`.
          goProxy = pkgs.stdenvNoCC.mkDerivation {
            name = "go-modules";
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./go.mod
                ./go.sum
                ./go.work
                ./go.work.sum
                ./tools/go.mod
                ./tools/go.sum
              ];
            };
            nativeBuildInputs = [
              go
              pkgs.cacert
              pkgs.gitMinimal
            ];
            buildPhase = ''
              export HOME=$TMPDIR GOPATH=$TMPDIR/go GOMODCACHE=$TMPDIR/mod GOTOOLCHAIN=local GOSUMDB=off
              GOWORK=off go mod download
              (cd tools && GOWORK=off go mod download)
              go mod download
            '';
            installPhase = ''
              rm -rf $GOMODCACHE/cache/download/sumdb
              cp -r $GOMODCACHE/cache/download $out
            '';
            dontFixup = true;
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-qkg+IDFru8zZ8K7nSgmi8RkDuQ2BXhOffIEOowzwPvo=";
          };

          # The subcharts that Chart.lock pins, fetched once, so a check renders a chart with no network.
          # A change to a Chart.lock changes the hash: run `just nix-hashes`.
          helmCharts = pkgs.stdenvNoCC.mkDerivation {
            name = "helm-charts";
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.fileFilter (f: f.name == "Chart.yaml" || f.name == "Chart.lock") ./infra/helm;
            };
            nativeBuildInputs = [
              pkgs.kubernetes-helm
              pkgs.cacert
            ];
            buildPhase = ''
              export HOME=$TMPDIR
              for lock in $(find infra/helm -name Chart.lock | sort); do
                dir=$(dirname "$lock")
                helm dependency build "$dir" >/dev/null 2>&1 || helm dependency update --skip-refresh "$dir" >/dev/null 2>&1 || helm dependency update "$dir"
                mkdir -p "$out/$dir"
                cp -r "$dir/charts" "$out/$dir/"
              done
            '';
            dontInstall = true;
            dontFixup = true;
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-Eb9PVvlVDJ8GEHsAr6XM3Z9dLTcletjNv8W7LcsQO34=";
          };

          # The tools of every gate. The dev shell holds them too, so a recipe runs the same way in both.
          # The scripts use the builtins of a full bash, such as compgen.
          gateTools = with pkgs; [
            bashInteractive
            go
            config.tabkit.go.golangci
            ast-grep
            sqlc
            sqruff
            dbmate
            vacuum-go
            oasdiff
            dnscontrol
            biome
            kubernetes-helm
            jq
            yq-go
            openfga-cli
            shellcheck
            shfmt
            gitleaks
            rumdl
            just
            gitMinimal
            nixfmt
            prometheus.cli
            inputs.tabkit.packages.${system}.tabkit-platform
            config.tabkit.rules.package
          ];

          # A gate runs its just recipes on the tracked files, with the locked node_modules, Go modules, and subcharts.
          gate =
            name: recipes:
            check name (gateTools ++ [ dprint ]) ''
              export IN_NIX_SHELL=pure HOME=$TMPDIR GOPATH=$TMPDIR/go GOCACHE=$TMPDIR/go-cache GOMODCACHE=$TMPDIR/go-mod
              export GOPROXY=file://${goProxy} GOSUMDB=off GOTOOLCHAIN=local GOFLAGS=-mod=readonly CGO_ENABLED=0
              export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-lint
              cp -r --no-preserve=mode ${helmCharts}/infra .
              # The tools list the repo files with git, and the sandbox has no .git. An index of the tracked files is enough.
              git init -q . && git add -A
              just ${recipes}
            '';
          # The dprint wrapper of tabkit, which passes the shared config and the plugins.
          dprint = lib.findFirst (
            p: lib.getName p == "dprint"
          ) (throw "no dprint in the dev shell") config.devShells.default.nativeBuildInputs;
          # Helm and Alertmanager templates are Go templates in a YAML file, and no YAML formatter parses them.
          # A SOPS file is signed over its exact text, so a formatter run would break its MAC.
          dprintExcludes = "--excludes '**/templates/**' '**/*.enc.yaml'";
        in
        {
          _module.args.pkgs = pkgs;

          tabkit.packages = gateTools ++ [
            # The frontend dev server and the Next.js build run on Node.js, per ADR-0110.
            pkgs.nodejs_26
            pkgs.gopls
            pkgs.typescript-language-server
            pkgs.kubectl
            pkgs.argocd
            pkgs.kustomize
            pkgs.cilium-cli
            pkgs.opentofu
            pkgs.kind
            pkgs.talosctl
            pkgs.age
            pkgs.sops
            pkgs.trivy
            cosign
            pkgs.oras
            pkgs.syft
            pkgs.act
            pkgs.k6
            pkgs.renovate
            pkgs.gnupg
            pkgs.openssl
            pkgs.curl
          ];

          tabkit.env = {
            GOFLAGS = "-mod=readonly";
            CGO_ENABLED = "0";
            GOTOOLCHAIN = "local";
          };

          # Every image builds with the toolchain of the dev shell, so CI tests what ships.
          tabkit.imageVersions = {
            GO_VERSION = go.version;
            NODE_VERSION = pkgs.nodejs_26.version;
            BUN_VERSION = config.tabkit.bun.package.version;
          };

          # Next.js needs the hoisted layout, which bunfig.toml also sets for each local and image install.
          tabkit.bun = {
            tools = [ pkgs.nodejs_26 ];
            installFlags = [ "--linker=hoisted" ];
            env.NEXT_TELEMETRY_DISABLED = "1";
          };

          # A fix stops the commit, so the engineer reviews the change and stages it.
          tabkit.hooks = {
            data = {
              name = "dprint";
              entry = "${dprint}/bin/dprint check --allow-no-files ${dprintExcludes} --";
              files = "\\.(jsonc?|toml|ya?ml)$";
              excludes = [
                "(^|/)templates/"
                "\\.enc\\.yaml$"
              ];
            };
            biome = {
              name = "biome";
              entry = "${pkgs.biome}/bin/biome check --config-path .config --write --no-errors-on-unmatched";
              files = "\\.(ts|tsx|js|jsx|cjs|mjs|css)$";
            };
            gofmt = {
              name = "golangci-lint fmt";
              # golangci-lint runs `go env` to find go.mod, so the hook carries the Go of the dev shell. GOTOOLCHAIN=local
              # stops Go from downloading another toolchain when go.mod names a newer one.
              entry = toString (
                pkgs.writeShellScript "golangci-lint-fmt" ''
                  export PATH=${go}/bin:$PATH GOTOOLCHAIN=local
                  exec ${config.tabkit.go.golangci}/bin/golangci-lint fmt --config .config/golangci.yml
                ''
              );
              files = "\\.go$";
              pass_filenames = false;
            };
          };

          # One shell for each workspace with its own tools, per ADR-0601 and ADR-0401. The default shell stays free of browsers.
          devShells = {
            # Playwright drives the browsers of nixpkgs, so @playwright/test in test/e2e matches playwright-driver.
            # Bun installs the suite from the root lockfile, and Node.js runs it, per ADR-0110.
            e2e = pkgs.mkShellNoCC {
              packages = [
                config.tabkit.bun.package
                pkgs.nodejs_26
                pkgs.just
                pkgs.git
                inputs.tabkit.packages.${system}.tabkit-platform
              ];
              env = {
                PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
                PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
                PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
              };
            };
            # The activity gates of CI decide whether a suite runs. Each job has five minutes, and the full dev shell
            # takes longer on a cold runner, so a gate gets only the tools that its script calls.
            gate = pkgs.mkShellNoCC {
              packages = [
                inputs.tabkit.packages.${system}.default
                inputs.tabkit.packages.${system}.tabkit-platform
                pkgs.just
                pkgs.go
                pkgs.git
                pkgs.jq
                pkgs.yq-go
                pkgs.curl
              ];
            };
          };

          # The two fixed-output derivations, so tabkit-ops nix-hashes can build each one alone.
          packages = {
            go-modules = goProxy;
            helm-charts = helmCharts;
          };

          checks = {
            lint-data = lib.mkForce (
              config.tabkit.check "lint-data" [
                dprint
              ] "DPRINT_CACHE_DIR=$TMPDIR/dprint dprint check ${dprintExcludes}"
            );
            build = gate "build" "build";
            test-go = gate "test-go" "test-go";
            test-ts = gate "test-ts" "test-ts test-frontend";
            test-alerts = gate "test-alerts" "test-alerts";
            lint-go = gate "lint-go" "lint-go lint-gostyle lint-template-build lint-determinism";
            lint-ts = gate "lint-ts" "lint-ts admin-lint";
            lint-platform = gate "lint-platform" "lint-platform";
            gen = gate "gen" "ci-gen";
            # The e2e shell runs the browsers of nixpkgs, so the test runner must be the same release, per ADR-0601.
            e2e-playwright = pkgs.runCommand "e2e-playwright" { nativeBuildInputs = [ pkgs.jq ]; } ''
              want=${pkgs.playwright-driver.version}
              have=$(jq -r '.devDependencies["@playwright/test"]' ${./test/e2e/package.json})
              [ "$have" = "$want" ] || { echo "@playwright/test is $have, and playwright-driver in nixpkgs is $want" >&2; exit 1; }
              touch $out
            '';
          };
        };
    };
}
