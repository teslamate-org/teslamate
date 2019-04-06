use Mix.Config

config :tesla_mate, TeslaMateWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  root: ".",
  server: true,
  version: Application.spec(:tesla_mate, :vsn)

config :logger, level: :info
