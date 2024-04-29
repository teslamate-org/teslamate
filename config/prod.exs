import Config

config :teslamate, TeslaMateWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  server: true,
  version: Application.spec(:teslamate, :vsn)

config :logger,
  level: String.to_atom(System.get_env("APP_LOG_LEVEL", "info"))

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:car_id]
