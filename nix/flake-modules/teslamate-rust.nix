{ ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      src = lib.cleanSourceWith {
        src = ../.. + "/rust";
        filter = name: type: baseNameOf (toString name) != "target";
      };

      pname = "teslamate-rust";
      version = lib.trim (builtins.readFile ../../VERSION);

      teslamate-rust = pkgs.rustPlatform.buildRustPackage {
        inherit pname version src;
        cargoLock = {
          lockFile = ../.. + "/rust/Cargo.lock";
        };
        buildInputs = [
          pkgs.postgresql
          pkgs.sqlite
        ];
        # The source above is rust/ only; the legal files live in the repository root.
        # Explicit target names, because store paths carry a hash prefix.
        postInstall = ''
          install -Dm444 ${../../NOTICE} $out/share/doc/teslamate-rust/NOTICE
          install -Dm444 ${../../LICENSE} $out/share/doc/teslamate-rust/LICENSE
        '';
        meta.license = lib.licenses.agpl3Plus;
        # build.rs reads ../VERSION, which lies outside the rust/ source.
        # The dashboard tests read the dashboards their queries port the
        # same way.
        postUnpack = ''
          cp ${../../VERSION} $sourceRoot/../VERSION
          install -Dm444 ${../../grafana/dashboards/vampire-drain.json} \
            $sourceRoot/../grafana/dashboards/vampire-drain.json
          install -Dm444 ${../../grafana/dashboards/drives.json} \
            $sourceRoot/../grafana/dashboards/drives.json
        '';
        # A Postgres for the vampire-drain comparison test, listening on a
        # Unix socket only, so the build sandbox needs no networking. Its
        # schema is the real one: the app's own migrations run through the
        # release's migrate task, on the socket like the NixOS module does.
        preCheck = ''
          export PGDATA="$NIX_BUILD_TOP/pgdata"
          "${pkgs.postgresql}/bin/initdb" \
            -D "$PGDATA" -U teslamate --auth=trust --no-locale --encoding=UTF8
          "${pkgs.postgresql}/bin/pg_ctl" -D "$PGDATA" -l "$NIX_BUILD_TOP/postgres.log" \
            -o "-k $PGDATA -c listen_addresses=" -w start
          "${pkgs.postgresql}/bin/createdb" -h "$PGDATA" -U teslamate teslamate_rust_test
          export DATABASE_SOCKET_DIR="$PGDATA"
          export DATABASE_USER="teslamate"
          export DATABASE_NAME="teslamate_rust_test"
          export DISABLE_MQTT="true"
          # The Nix release has no baked cookie file; any value does, the
          # migrate task runs on one node only.
          export RELEASE_COOKIE="teslamate-rust-test"
          ${config.teslamate.package}/bin/teslamate eval "TeslaMate.Release.migrate"
          export TEST_DATABASE_URL="postgresql:///teslamate_rust_test?host=$PGDATA&user=teslamate"
        '';
        postCheck = ''
          "${pkgs.postgresql}/bin/pg_ctl" -D "$PGDATA" -m immediate stop
        '';
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
