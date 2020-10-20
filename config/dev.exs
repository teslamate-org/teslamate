import Config

config :teslamate, TeslaMateWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--stats-colors",
      "--watch",
      "--watch-options-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/teslamate_web/(live|views)/.*(ex)$",
      ~r"lib/teslamate_web/templates/.*(eex)$",
      ~r"grafana/dashboards/.*(json)$"
    ]
  ]

config :logger, :console, format: "$metadata[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :teslamate, TeslaMate.Repo, show_sensitive_data_on_connection_error: true
config :teslamate, disable_token_refresh: true
