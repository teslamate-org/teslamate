use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teslamate, TeslaMateWeb.Endpoint,
  http: [port: 4002],
  server: false

config :logger, level: :warn

config :teslamate, TeslaMate.Repo,
  username: "postgres",
  password: "postgres",
  database: "teslamate_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :teslamate, :tesla_auth,
  username: "admin",
  password: "admin"
