import Config

config :teslamate,
  ecto_repos: [TeslaMate.Repo]

config :teslamate, TeslaMateWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Kz7vmP1gPYv/sogke6P3RP9uipMjOLhneQdbokZVx5gpLsNaN44TD20vtOWkMFIT",
  render_errors: [view: TeslaMateWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: TeslaMate.PubSub,
  live_view: [signing_salt: "6nSVV0NtBtBfA9Mjh+7XaZANjp9T73XH"]

config :teslamate,
  cloak_repo: TeslaMate.Repo,
  cloak_schemas: [
    TeslaMate.Auth.Tokens
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:car_id]

config :phoenix,
  json_library: Jason,
  static_compressors: [
    PhoenixBakery.Gzip,
    PhoenixBakery.Brotli,
    PhoenixBakery.Zstd
  ]

config :gettext, :default_locale, "en"

# Localize is used for UI-language negotiation only (translations come
# from Gettext, dates from Timex). The release deliberately ships no
# per-locale CLDR data — negotiation needs none — so Localize formatting
# APIs (Number/DateTime/Unit) would raise LocaleNotFoundInCacheError for
# any locale but "en". Keep formatting a non-goal, or wire
# `mix localize.download_locales` into the build first.
#
# Static list so compile-time Localize calls see the same set as runtime.
# Use CLDR IDs (hyphens, :"zh-Hans") — expanding Gettext names like
# "zh_Hans" collapses to :zh via likely subtags and loses zh-Hant.
config :localize,
  otp_app: :teslamate,
  default_locale: :en,
  allow_runtime_locale_download: false,
  supported_locales: [
    :ca,
    :da,
    :de,
    :en,
    :es,
    :fi,
    :fr,
    :hu,
    :it,
    :ja,
    :ko,
    :nb,
    :nl,
    :sv,
    :th,
    :tr,
    :uk,
    :"zh-Hans",
    :"zh-Hant"
  ]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

import_config "#{config_env()}.exs"
