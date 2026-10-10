import Config

config :teslamate, TeslaMateWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  server: true,
  version: Application.spec(:teslamate, :vsn)

config :logger,
  level: :info

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:car_id]
