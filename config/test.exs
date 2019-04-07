use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teslamate, TeslaMateWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :teslamate, TeslaMate.Repo,
  username: "adrian",
  password: "postgres",
  database: "teslamate_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :teslamate, :tesla_auth,
  username: "admin",
  password: "admin"
