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
              nodes.server =
                { pkgs, ... }:
                let
                  secretsDir = "teslamate-test";
                  # Read by systemd as EnvironmentFile, never by Nix.
                  secretsFile = "/run/${secretsDir}/secrets.env";
                  consumers = [
                    "postgresql-setup.service"
                    "teslamate.service"
                    "grafana.service"
                  ];
                in
                {
                  imports = [ self.nixosModules.default ];
                  virtualisation.cores = 4;
                  virtualisation.memorySize = 2048;

                  services.teslamate = {
                    enable = true;
                    inherit secretsFile;
                    postgres.enable_server = true;
                    grafana.enable = true;
                  };

                  # Fresh random secrets on every boot, so no fixed credentials
                  # land in the world-readable Nix store.
                  systemd.services.teslamate-test-secrets = {
                    before = consumers;
                    requiredBy = consumers;
                    path = [ pkgs.openssl ];
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      RuntimeDirectory = secretsDir;
                      UMask = "0077";
                    };
                    script = ''
                      # A plain assignment, so set -e stops on an openssl failure
                      # instead of writing an empty value.
                      for key in ENCRYPTION_KEY DATABASE_PASS RELEASE_COOKIE; do
                        value="$(openssl rand -hex 32)"
                        echo "$key=$value"
                      done > ${secretsFile}
                    '';
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
