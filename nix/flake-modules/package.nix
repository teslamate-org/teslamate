{ ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_29;
      elixir = beamPackages.elixir_1_20;
      rebar3 = beamPackages.rebar3;

      src = ../..;
      version = builtins.readFile "${src}/VERSION";
      pname = "teslamate";

      mixFodDeps = beamPackages.fetchMixDeps {
        TOP_SRC = src;
        pname = "${pname}-mix-deps";
        inherit src version;
        hash = "sha256-/AVC3lmmkqptB4c523zkgDWrwJ9luXZitKK54fOLI5Q="; # if you change the mix deps, you need to update this hash
        # hash = pkgs.lib.fakeHash;
      };

      nodejs = pkgs.nodejs;
      assetsRoot = src + "/assets";

      # assets/package-lock.json links phoenix, phoenix_html and
      # phoenix_live_view as `file:../deps/*`. That directory only exists in a
      # working tree after `mix deps.get`, so the already fetched mix deps are
      # substituted for them here. Every other dependency is fetched from the
      # integrity hashes in package-lock.json, which is why this needs no
      # aggregate hash of its own.
      npmSources = pkgs.importNpmLock {
        npmRoot = assetsRoot;
        packageSourceOverrides = {
          "node_modules/phoenix" = "${mixFodDeps}/phoenix";
          "node_modules/phoenix_html" = "${mixFodDeps}/phoenix_html";
          "node_modules/phoenix_live_view" = "${mixFodDeps}/phoenix_live_view";
        };
      };

      nodePackages = pkgs.importNpmLock.buildNodeModules {
        npmRoot = assetsRoot;
        inherit nodejs;
        derivationArgs = {
          pname = "${pname}-assets";
          inherit version;
          # Overrides the sources buildNodeModules would derive itself, so that
          # the phoenix packages resolve to mixFodDeps (see npmSources above).
          npmDeps = npmSources;
          postInstall = ''
            ln -s $out/node_modules/.bin $out/bin
          '';
        };
      };

      teslamate = beamPackages.mixRelease {
        TOP_SRC = src;
        inherit
          pname
          version
          elixir
          src
          mixFodDeps
          ;

        postBuild = ''
          ln -sf ${mixFodDeps}/deps deps
          ln -sf ${nodePackages}/node_modules assets/node_modules
          export PATH="${pkgs.nodejs}/bin:${nodePackages}/bin:$PATH"
          ${nodejs}/bin/npm run deploy --prefix ./assets

          # for external task you need a workaround for the no deps check flag
          # https://github.com/phoenixframework/phoenix/issues/2690
          mix do deps.loadpaths --no-deps-check, phx.digest
          mix phx.digest --no-deps-check
        '';

        meta = {
          mainProgram = "teslamate";
        };
      };
    in
    {
      options = {
        teslamate.elixir = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
        teslamate.rebar3 = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
      };

      config = {
        teslamate = {
          inherit elixir rebar3;
        };

        packages = {
          default = teslamate;
        };
      };
    };
}
