{ self, inputs, ... }:
{
  perSystem =
    { self'
    , pkgs
    , lib
    , ...
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
    in
    {
      checks =
        if pkgs.stdenv.isLinux then {
          default = moduleTest;
        } else { };
    };
}
