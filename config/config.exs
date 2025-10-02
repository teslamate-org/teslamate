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

config :logger,
  backends:
    [
      :console
    ] ++
      if(System.get_env("TESLAMATE_FILE_LOGGING_ENABLED") == "true",
        do: [{Logger.Handlers.File, :file_logger_for_webview}],
        else: []
      ),
  console: [
    format: "$time $metadata[$level] $message\n",
    metadata: [:car_id]
  ],
  file_logger_for_webview: [
    format: "$time $metadata[$level] $message\n",
    metadata: [:car_id],
    path:
      System.get_env("TESLAMATE_FILE_LOGGING_PATH") ||
        Path.join(File.cwd!(), "data/logs/teslamate.log"),
    # sync every 5 messages to file
    sync_threshold: 5
  ]

config :phoenix, :json_library, Jason

config :gettext, :default_locale, "en"

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

import_config "#{config_env()}.exs"
