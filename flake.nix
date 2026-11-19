# The toolchain, the git hooks, the island shells, and the checks, per ADR-0100 and ADR-0111.
# The tabnix module holds every shared part, and this file adds the parts of the platform.
{
  description = "A self-hosted platform monorepo, with every reusable decision recorded as an ADR and enforced in CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # A new version is a new tag here.
    tabnix = {
      url = "github:tabmadi/tabnix/v0.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    inputs@{ flake-parts, tabnix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # The template scope adds its own checks and outputs. A copy has no template/ folder, so it adds nothing.
      # The bun module of tabnix holds Bun, bun2nix, the hook for bun.nix, and the install and check helpers.
      imports = [
        tabnix.flakeModules.default
        tabnix.flakeModules.bun
      ]
      ++ inputs.nixpkgs.lib.optional (builtins.pathExists ./template/scope.nix) ./template/scope.nix;

      # The cluster tools and the image builds run on Linux. The tools of a workstation also run on macOS.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          lib,
          system,
          ...
        }:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};

          inherit (config.tabnix.bun) check;

          # cosign stays on 2.x, per ADR-0113: cosign 3 writes only the Sigstore bundle format,
          # and Kyverno verifies that format through the public TUF root, which ADR-0113 rejects.
          cosign = pkgs.cosign.overrideAttrs {
            version = "2.6.5";
            src = pkgs.fetchFromGitHub {
              owner = "sigstore";
              repo = "cosign";
              rev = "v2.6.5";
              hash = "sha256-tJNNGHT8wFRcVR3/9y2xBAWymBF57zrYUSMtgDU5EPs=";
            };
            vendorHash = "sha256-6dHMqmiMxe0mPMyo/TMGcMxzViGp7H3gaS2uTAtrvU4=";
          };
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
            outputHash = "sha256-iqfy2D5abhrC1yQMudW269ZaVm2NR/X2ipg+bPiRe5Y=";
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
            outputHash = "sha256-fuGkfWYtVU15/UVyj9JKp3hhfEMKJ9Mh1SSHhZs8BkY=";
          };

          # The tools of every gate. The dev shell holds them too, so a recipe runs the same way in both.
          # The scripts use the builtins of a full bash, such as compgen.
          gateTools = with pkgs; [
            bashInteractive
            go
            golangci-lint
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
            config.tabnix.tablint
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
          # The dprint wrapper of tabnix, which passes the shared config and the plugins.
          dprint = lib.findFirst (
            p: lib.getName p == "dprint"
          ) (throw "no dprint in the dev shell") config.devShells.default.nativeBuildInputs;
          # Helm and Alertmanager templates are Go templates in a YAML file, and no YAML formatter parses them.
          dprintExcludes = "--excludes '**/templates/**'";
        in
        {
          _module.args.pkgs = pkgs;

          tabnix.packages = gateTools ++ [
            # The frontend dev server and the Next.js build run on Node.js, per ADR-0110.
            pkgs.nodejs_24
            pkgs.gopls
            pkgs.typescript-language-server
            pkgs.kubectl
            pkgs.argocd
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

          tabnix.env = {
            GOFLAGS = "-mod=readonly";
            CGO_ENABLED = "0";
            GOTOOLCHAIN = "local";
          };

          # Next.js needs the hoisted layout of a plain `bun install`.
          tabnix.bun = {
            tools = [ pkgs.nodejs_24 ];
            installFlags = [ "--linker=hoisted" ];
            env.NEXT_TELEMETRY_DISABLED = "1";
          };

          # A fix stops the commit, so the engineer reviews the change and stages it.
          tabnix.hooks = {
            data = {
              name = "dprint";
              entry = "${dprint}/bin/dprint check ${dprintExcludes}";
              files = "\\.(jsonc?|toml|ya?ml)$";
              excludes = [ "(^|/)templates/" ];
            };
            biome = {
              name = "biome";
              entry = "${pkgs.biome}/bin/biome check --config-path .config --write --no-errors-on-unmatched";
              files = "\\.(ts|tsx|js|jsx|cjs|mjs|css)$";
            };
            gofmt = {
              name = "golangci-lint fmt";
              entry = "${pkgs.golangci-lint}/bin/golangci-lint fmt --config .config/golangci.yml";
              files = "\\.go$";
              pass_filenames = false;
            };
            shfmt = {
              name = "shfmt";
              entry = "${pkgs.shfmt}/bin/shfmt --diff";
              files = "\\.sh$";
            };
          };

          # One shell per Node island, per ADR-0601 and ADR-0401. The default shell stays free of browsers.
          devShells = {
            # Playwright drives the browsers of nixpkgs, so @playwright/test in test/e2e matches playwright-driver.
            e2e = pkgs.mkShellNoCC {
              packages = [
                pkgs.nodejs_24
                pkgs.just
              ];
              env = {
                PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
                PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
                PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
              };
            };
            # Lowdefy's CLI needs pnpm and Node.js, per ADR-0401.
            admin = pkgs.mkShellNoCC {
              packages = [
                pkgs.nodejs_24
                pkgs.pnpm
                pkgs.just
              ];
            };
          };

          # The two fixed-output derivations, so scripts/nix-hashes.sh can build each one alone.
          packages = {
            go-modules = goProxy;
            helm-charts = helmCharts;
          };

          checks = {
            lint-data = lib.mkForce (
              config.tabnix.check "lint-data" [
                dprint
              ] "DPRINT_CACHE_DIR=$TMPDIR/dprint dprint check ${dprintExcludes}"
            );
            build = gate "build" "build";
            test-go = gate "test-go" "test-go";
            test-ts = gate "test-ts" "test-ts test-frontend";
            lint-go = gate "lint-go" "lint-go lint-gostyle lint-template-build lint-determinism";
            lint-ts = gate "lint-ts" "lint-ts";
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
