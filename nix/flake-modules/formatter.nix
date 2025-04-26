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
    };
}
