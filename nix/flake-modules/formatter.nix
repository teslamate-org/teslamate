{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];
  perSystem =
    { config, pkgs, ... }:
    let
      # treefmt.toml is generated from the treefmt settings below so that the
      # two can not drift apart (see checks.treefmt-toml). The only difference
      # is the `command` of each formatter: the Nix config pins absolute store
      # paths, while contributors without Nix need the bare binary name from
      # their PATH.
      treefmtTomlHeader = ''
        # One CLI to format the code tree - https://git.numtide.com/numtide/treefmt
        #
        # GENERATED FILE - DO NOT EDIT.
        # Source of truth: nix/flake-modules/formatter.nix
        # Regenerate with: nix run .#update-treefmt-toml
        #
        # This copy exists for contributors without Nix, who run a bare `treefmt`.
        # Nix users (`nix fmt`, `nix run .#lint`) and CI use the generated config
        # directly and never read this file. Note that it resolves formatters from
        # PATH, so their versions are not pinned the way the Nix config pins them.
      '';

      generatedTreefmtToml = pkgs.runCommand "treefmt.toml" { } ''
        cat ${pkgs.writeText "treefmt-toml-header" treefmtTomlHeader} > $out
        echo >> $out
        # Reduce the pinned store paths to bare binary names, resolved from PATH.
        sed -E 's|"/nix/store/[^"]*/|"|' ${config.treefmt.build.configFile} >> $out
      '';

      # treefmt.toml must stay byte-identical to what the treefmt settings
      # generate, otherwise contributors without Nix format against a stale
      # config and CI rejects their result.
      treefmtTomlInSync = pkgs.runCommand "treefmt-toml-in-sync" { } ''
        if ! diff -u ${../../treefmt.toml} ${generatedTreefmtToml}; then
          echo >&2
          echo "treefmt.toml is out of sync with nix/flake-modules/formatter.nix." >&2
          echo "Regenerate it with: nix run .#update-treefmt-toml" >&2
          exit 1
        fi
        touch $out
      '';
    in
    {
      # Auto formatters. This also adds a flake check to ensure that the
      # source tree was auto formatted.
      treefmt = {
        flakeFormatter = true; # Enables treefmt the default formatter used by the nix fmt command
        flakeCheck = false; # Add a flake check to run treefmt, disabled, as mix format does need the dependencies fetched beforehand
        projectRootFile = "VERSION"; # File used to identity repo root

        settings.global.excludes = [
          "*.gitignore"
          "*.dockerignore"
          ".envrc"
          "*.node-version"
          "CONTRIBUTING"
          "Dockerfile"
          "grafana/Dockerfile"
          "Makefile"
          "VERSION"
          "LICENSE"
          "*.metadata"
          "*.manifest"
          "*.webmanifest"
          "*.dat"
          "*.lock"
          "*.txt"
          "*.csv"
          "*.ico"
          "*.png"
          "*.svg"
          "*.properties"
          "*.xml"
          "*.po"
          "*.pot"
          "*.json.example"
          "*.typos.toml"
          "treefmt.toml"
          "grafana/dashboards/*.json" # we use the grafana export style
        ];
        programs.mix-format.enable = true;
        programs.mix-format.package = config.teslamate.elixir;
        settings.formatter.mix-format.includes = [
          "*.ex"
          "*.exs"
          "*.{heex,eex}"
        ];
        # run shellcheck first
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.priority = 0; # default is 0, but we set it here for clarity

        # shfmt second
        programs.shfmt.enable = true;
        programs.shfmt.indent_size = 0; # 0 means tabs
        settings.formatter.shfmt.priority = 1;

        programs.prettier.enable = true;

        programs.nixfmt.enable = true;
      };

      # Exposed twice on purpose: as a check so `nix flake check` covers it, and
      # as a package so CI can build it as `.#check-treefmt-toml`, which resolves
      # the current system instead of hardcoding one.
      checks.treefmt-toml = treefmtTomlInSync;
      packages.check-treefmt-toml = treefmtTomlInSync;

      # Writes next to the root marker treefmt itself anchors on, rather than
      # deriving a second notion of the project root.
      packages.update-treefmt-toml = pkgs.writeShellApplication {
        name = "update-treefmt-toml";
        text = ''
          if [ ! -f ${config.treefmt.projectRootFile} ]; then
            echo "run this from the project root (no ${config.treefmt.projectRootFile} here)" >&2
            exit 1
          fi
          install -m 644 ${generatedTreefmtToml} treefmt.toml
          echo "wrote treefmt.toml"
        '';
      };

      # Lean treefmt entrypoint for CI: `nix run .#lint -- --ci`
      # (locally just `nix run .#lint`; any extra args are passed to treefmt).
      #
      # The default devenv shell pulls in the whole development closure
      # (elixir-ls, postgres, nodejs, mosquitto, osv-scanner, …), which is
      # several GB and does not fit the cache GC budget, so CI rebuilds it on
      # every run. Linting only needs the treefmt wrapper (which already bundles
      # all formatters via absolute store paths) plus Elixir, which is the same
      # one as the release (see package.nix), so the formatter runs against the
      # project's toolchain. mix-format needs its plugin
      # (Phoenix.LiveView.HTMLFormatter) and that plugin's deps compiled, so
      # MIX_REBAR3 is pinned (a clean CI MIX_HOME has no rebar3), mirroring the
      # devenv shell. mix deps.get fetches the formatter plugin deps first.
      packages.lint = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = [
          config.teslamate.elixir
          config.treefmt.build.wrapper
        ];
        runtimeEnv.MIX_REBAR3 = "${config.teslamate.rebar3}/bin/rebar3";
        text = ''
          mix deps.get
          exec treefmt "$@"
        '';
      };
    };
}
