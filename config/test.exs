use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tesla_mate, TeslaMateWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :tesla_mate, TeslaMate.Repo,
  username: "adrian",
  password: "postgres",
  database: "tesla_mate_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :tesla_mate, :tesla_auth,
  username: "admin",
  password: "admin"
