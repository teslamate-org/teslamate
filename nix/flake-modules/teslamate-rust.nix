{ ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      ...
    }:
    let
      src = lib.cleanSourceWith {
        src = ../.. + "/teslamate-rust";
        filter = name: type: baseNameOf (toString name) != "target";
      };

      pname = "teslamate-rust";
      version = "0.1.0";

      teslamate-rust = pkgs.rustPlatform.buildRustPackage {
        inherit pname version src;
        cargoLock = {
          lockFile = ../.. + "/teslamate-rust/Cargo.lock";
        };
      };
    in
    {
      options = {
        teslamate-rust = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
      };

      config = {
        teslamate-rust = teslamate-rust;

        packages.teslamate-rust = teslamate-rust;
      };
    };
}
