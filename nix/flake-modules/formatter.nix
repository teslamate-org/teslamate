{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];
  perSystem =
    { config, pkgs, ... }:
    {
      # Auto formatters. This also adds a flake check to ensure that the
      # source tree was auto formatted.
      treefmt = {
        flakeFormatter = true; # Enables treefmt the default formatter used by the nix fmt command
        flakeCheck = false; # Add a flake check to run treefmt, disabled, as mix format does need the dependencies fetched beforehand
        projectRootFile = "VERSION"; # File used to identity repo root

        # we really need to mirror the treefmt.toml as we can't use it directly
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

        programs.nixpkgs-fmt.enable = true;
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
