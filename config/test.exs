import Config

config :logger, level: :warning

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :teslamate, TeslaMateWeb.Endpoint, server: false
config :teslamate, TeslaMate.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :phoenix, :plug_init_mode, :runtime

# API configuration for tests
config :teslamate, :api,
  enabled: true,
  auth_token: "test_api_token",
  jwt_secret: "test_jwt_secret_at_least_32_bytes_long_for_hs256!"

config :joken,
  default_signer: [
    signer_alg: "HS256",
    key_octet: "test_jwt_secret_at_least_32_bytes_long_for_hs256!"
  ]
