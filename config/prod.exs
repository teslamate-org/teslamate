import Config

config :teslamate, TeslaMateWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  server: true,
  version: Application.spec(:teslamate, :vsn)

config :logger,
  level: :info,
  compile_time_purge_matching: [[level_lower_than: :info]]

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:car_id]
