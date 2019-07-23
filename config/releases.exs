import Config

defmodule Util do
  def random_encoded_bytes do
    :crypto.strong_rand_bytes(6) |> Base.encode64()
  end
end

config :gettext, :default_locale, System.get_env("LOCALE")

config :teslamate, TeslaMate.Repo,
  username: System.fetch_env!("DATABASE_USER"),
  password: System.fetch_env!("DATABASE_PASS"),
  database: System.fetch_env!("DATABASE_NAME"),
  hostname: System.fetch_env!("DATABASE_HOST"),
  pool_size: System.get_env("DATABASE_POOL_SIZE", "15") |> String.to_integer()

config :teslamate, TeslaMateWeb.Endpoint,
  http: [:inet6, port: System.get_env("PORT", "4000")],
  url: [host: System.get_env("VIRTUAL_HOST", "localhost"), port: 80],
  secret_key_base: System.get_env("SECRET_KEY_BASE", Util.random_encoded_bytes()),
  live_view: [signing_salt: System.get_env("SIGNING_SALT", Util.random_encoded_bytes())]

config :teslamate, :tesla_auth,
  username: System.fetch_env!("TESLA_USERNAME"),
  password: System.fetch_env!("TESLA_PASSWORD")

if System.get_env("DISABLE_MQTT") != "true" do
  config :teslamate, :mqtt,
    host: System.fetch_env!("MQTT_HOST"),
    username: System.get_env("MQTT_USERNAME"),
    password: System.get_env("MQTT_PASSWORD")
end

config :logger,
  level: :info,
  compile_time_purge_matching: [[level_lower_than: :info]]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: []

if System.get_env("ENABLE_LOGGER_TELEGRAM") == "true" do
  config :logger,
    backends: [LoggerTelegramBackend, :console]

  config :logger, :telegram,
    level: :error,
    chat_id: System.fetch_env!("CHAT_ID"),
    token: System.fetch_env!("TOKEN")
end
