import Config

config :teslamate, TeslaMateWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  server: true,
  version: Application.spec(:teslamate, :vsn)

log_level = System.get_env("LOG_LEVEL", "info")
log_level_atom = String.to_existing_atom(log_level)

config :logger,
  level: log_level_atom

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:car_id]
