{ ... }:
{
  perSystem =
    { lib
    , pkgs
    , system
    , ...
    }:
    let
      beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_28;
      elixir = beamPackages.elixir_1_19;
      rebar3 = beamPackages.rebar3;

      src = ../..;
      version = builtins.readFile "${src}/VERSION";
      pname = "teslamate";

      mixFodDeps = beamPackages.fetchMixDeps {
        TOP_SRC = src;
        pname = "${pname}-mix-deps";
        inherit src version;
        hash = "sha256-KzbvAtJR1TFQuWFVcJBilA3aH4SdfBvVc+eq26dwxwE="; # if you change the mix deps, you need to update this hash
        # hash = pkgs.lib.fakeHash;
      };

      nodejs = pkgs.nodejs;
      nodePackages = pkgs.buildNpmPackage {
        name = "${pname}-assets";
        src = "${src}/assets";
        npmDepsHash = "sha256-CD0IaoMxaBcoAHMJusIn0e0mDo962wLKp6lWjFIb/gI="; # if you change the npm deps, you need to update this hash
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
        rev = "v2.47.4"; # this must match the version in the mix file
        sha256 = "sha256-LIQK6pZRAW1T3Ej2XAjnuPo82hPJ2KiMPWYmHWgx008="; # if you change the cldr version in the mix file, you need to update this hash
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

        # set the environment variables for the build
        SKIP_LOCALE_DOWNLOAD = "true"; # do not download locales during build as they are already included in the cldr package from github
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
        teslamate.rebar3 = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
        };
      };

      config = {
        teslamate = {
          inherit cldr elixir rebar3;
        };

        packages = {
          default = teslamate;
        };
      };
    };
}
