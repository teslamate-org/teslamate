{ ... }:
{
  perSystem = { lib, pkgs, system, ... }:
    let
      elixir = pkgs.beam.packages.erlang_26.elixir_1_17;
      beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_26;

      src = ../..;
      version = builtins.readFile "${src}/VERSION";
      pname = "teslamate";

      mixFodDeps = beamPackages.fetchMixDeps {
        TOP_SRC = src;
        pname = "${pname}-mix-deps";
        inherit src version;
        hash = "sha256-eJlaKYIitGGMq5ll5N3vQQLlZKl6/s3fAT771qv+MnE=";
        # hash = pkgs.lib.fakeHash;
      };

      nodejs = pkgs.nodejs;
      nodePackages = pkgs.buildNpmPackage {
        name = "${pname}-assets";
        src = "${src}/assets";
        npmDepsHash = "sha256-05AKPyms4WP8MHBqWMup8VXR3a1tv/f/7jT8c6EpWBw=";
        # npmDepsHash = pkgs.lib.fakeHash;
        dontNpmBuild = true;
        inherit nodejs;

        installPhase = ''
          mkdir $out
          cp -r node_modules $out
          ln -s $out/node_modules/.bin $out/bin

          rm $out/node_modules/phoenix
          ln -s ${mixFodDeps}/phoenix $out/node_modules

          rm $out/node_modules/phoenix_html
          ln -s ${mixFodDeps}/phoenix_html $out/node_modules

          rm $out/node_modules/phoenix_live_view
          ln -s ${mixFodDeps}/phoenix_live_view $out/node_modules
        '';
      };

      cldr = pkgs.fetchFromGitHub {
        owner = "elixir-cldr";
        repo = "cldr";
        rev = "v2.40.0";
        sha256 = "sha256-B3kIJx684kg3uxdFaWWMn9SBktb1GUqCzSJwN1a0oNo=";
        # sha256 = pkgs.lib.fakeHash;
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

        LOCALES = "${cldr}/priv/cldr";

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
        teslamate.cldr = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
        teslamate.elixir = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
      };

      config = {
        teslamate = {
          inherit cldr elixir;
        };

        packages = {
          default = teslamate;
        };
      };
    };
}
