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
        hash = "sha256-UnYICURIAWfhFogKlRkWZyVBQlkoJWToZ7YbrjsbET0="; # if you change the mix deps, you need to update this hash
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

      # The locale data must come from the same release as the ex_cldr version
      # resolved in mix.lock. Reading the version from the lockfile keeps the
      # two from drifting apart; a stale rev otherwise builds green and just
      # ships the wrong locales.
      cldrVersion =
        let
          matches = lib.filter (match: match != null) (
            map (builtins.match ''^ *"ex_cldr": \{:hex, :ex_cldr, "([^"]+)".*'') (
              lib.splitString "\n" (builtins.readFile "${src}/mix.lock")
            )
          );
        in
        if matches == [ ] then
          throw "could not determine the ex_cldr version from mix.lock"
        else
          lib.head (lib.head matches);

      cldr = pkgs.fetchFromGitHub {
        owner = "elixir-cldr";
        repo = "cldr";
        rev = "v${cldrVersion}";
        sha256 = "sha256-nGVuv8jyGCMZS63ga2iObjl+ldIZmM/xDfpQbB/ZRjE="; # if the ex_cldr version in mix.lock changes, you need to update this hash
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
