import Config

config :teslamate,
  ecto_repos: [TeslaMate.Repo]

config :teslamate, TeslaMateWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Kz7vmP1gPYv/sogke6P3RP9uipMjOLhneQdbokZVx5gpLsNaN44TD20vtOWkMFIT",
  render_errors: [view: TeslaMateWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: TeslaMate.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [
    signing_salt: "6nSVV0NtBtBfA9Mjh+7XaZANjp9T73XH"
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :gettext, :default_locale, "de"

import_config "#{Mix.env()}.exs"
