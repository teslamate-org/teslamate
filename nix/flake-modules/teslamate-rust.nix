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
        src = ../.. + "/rust";
        filter = name: type: baseNameOf (toString name) != "target";
      };

      pname = "teslamate-rust";
      version = "0.1.0";

      teslamate-rust = pkgs.rustPlatform.buildRustPackage {
        inherit pname version src;
        cargoLock = {
          lockFile = ../.. + "/rust/Cargo.lock";
        };
      };

      # Same source, deps and toolchain as the package; the build phase runs
      # clippy instead of cargo build and the derivation produces no output.
      teslamate-rust-clippy = teslamate-rust.overrideAttrs (old: {
        pname = "${pname}-clippy";
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.clippy ];
        buildPhase = ''
          runHook preBuild
          cargo clippy --all-targets --all-features -- -D warnings
          runHook postBuild
        '';
        doCheck = false;
        installPhase = "touch $out";
      });
    in
    {
      options = {
        teslamate-rust = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
        teslamate-rust-clippy = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
      };

      config = {
        teslamate-rust = teslamate-rust;
        teslamate-rust-clippy = teslamate-rust-clippy;

        packages.teslamate-rust = teslamate-rust;
        packages.teslamate-rust-clippy = teslamate-rust-clippy;
      };
    };
}
