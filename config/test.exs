import Config

config :logger, level: :warning

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teslamate, TeslaMateWeb.Endpoint, server: false
config :teslamate, TeslaMate.Repo, pool: Ecto.Adapters.SQL.Sandbox
