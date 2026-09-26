{ self, inputs, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (inputs) nixpkgs;
      moduleTest =
        (nixpkgs.lib.nixos.runTest {
          hostPkgs = pkgs;
          defaults.documentation.enable = false;
          imports = [
            {
              name = "teslamate";
              nodes.server = {
                imports = [ self.nixosModules.default ];
                virtualisation.cores = 4;
                virtualisation.memorySize = 2048;

                services.teslamate = {
                  enable = true;
                  secretsFile = builtins.toFile "teslamate.env" ''
                    ENCRYPTION_KEY=123456789
                    DATABASE_PASS=123456789
                    RELEASE_COOKIE=123456789
                  '';
                  postgres.enable_server = true;
                  grafana.enable = true;
                };
              };

              testScript = ''
                server.wait_for_open_port(4000)
              '';
            }
          ];
        }).config.result;

      # Every file must declare copyright and license: REUSE.toml covers the
      # repository, LICENSES/ holds the license texts. The flake source holds
      # only tracked files, so nothing gitignored is checked.
      reuseCompliance = pkgs.runCommand "reuse-compliance" { nativeBuildInputs = [ pkgs.reuse ]; } ''
        reuse --root ${self} lint
        touch $out
      '';
    in
    {
      # Also a package, so CI can build it as `.#check-reuse` for the current
      # system instead of hardcoding one, like `.#check-treefmt-toml`.
      packages.check-reuse = reuseCompliance;

      checks = {
        reuse = reuseCompliance;
        teslamate-rust = config.teslamate-rust;
        teslamate-rust-clippy = config.teslamate-rust-clippy;
      }
      // (
        if pkgs.stdenv.isLinux then
          {
            default = moduleTest;
          }
        else
          { }
      );
    };
}
