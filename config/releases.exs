import Config

config :teslamate, TeslaMate.Repo,
  username: System.fetch_env!("DATABASE_USER"),
  password: System.fetch_env!("DATABASE_PASS"),
  database: System.fetch_env!("DATABASE_NAME"),
  hostname: System.fetch_env!("DATABASE_HOST"),
  pool_size: 15

config :teslamate, TeslaMateWeb.Endpoint,
  http: [:inet6, port: System.get_env("PORT", "4000")],
  url: [host: System.get_env("VIRTUAL_HOST", "localhost"), port: 80],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  live_view: [
    signing_salt: System.fetch_env!("SIGNING_SALT")
  ]

config :teslamate, :tesla_auth,
  username: System.fetch_env!("TESLA_USERNAME"),
  password: System.fetch_env!("TESLA_PASSWORD")

config :teslamate, :mqtt,
  host: System.fetch_env!("MQTT_HOST"),
  username: System.fetch_env!("MQTT_USERNAME"),
  password: System.fetch_env!("MQTT_PASSWORD")

config :logger,
  backends: [LoggerTelegramBackend, :console],
  level: :info,
  handle_otp_reports: true,
  handle_sasl_reports: false,
  compile_time_purge_level: :info

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: []

config :logger, :telegram,
  level: :error,
  chat_id: System.fetch_env!("CHAT_ID"),
  token: System.fetch_env!("TOKEN")

config :teslamate, :mqtt,
  host: System.fetch_env!("MQTT_HOST"),
  username: System.fetch_env!("MQTT_USERNAME"),
  password: System.fetch_env!("MQTT_PASSWORD")
