import Config

defmodule Util do
  def random_encoded_bytes do
    :crypto.strong_rand_bytes(64) |> Base.encode64()
  end

  def validate_locale!("en"), do: "en"
  def validate_locale!("de"), do: "de"
  def validate_locale!(lang), do: raise("Unsupported locale: #{inspect(lang)}")

  def parse_check_origin!("true"), do: true
  def parse_check_origin!("false"), do: false
  def parse_check_origin!(hosts) when is_binary(hosts), do: String.split(hosts, ",")
  def parse_check_origin!(hosts), do: raise("Invalid check_origin option: #{inspect(hosts)}")
end

config :gettext,
       :default_locale,
       System.get_env("LOCALE", "en") |> Util.validate_locale!()

config :teslamate, TeslaMate.Repo,
  username: System.fetch_env!("DATABASE_USER"),
  password: System.fetch_env!("DATABASE_PASS"),
  database: System.fetch_env!("DATABASE_NAME"),
  hostname: System.fetch_env!("DATABASE_HOST"),
  port: System.get_env("DATABASE_PORT", "5432"),
  pool_size: System.get_env("DATABASE_POOL_SIZE", "8") |> String.to_integer()

config :teslamate, TeslaMateWeb.Endpoint,
  http: [:inet6, port: System.get_env("PORT", "4000")],
  url: [host: System.get_env("VIRTUAL_HOST", "localhost"), port: 80],
  secret_key_base: System.get_env("SECRET_KEY_BASE", Util.random_encoded_bytes()),
  live_view: [signing_salt: System.get_env("SIGNING_SALT", Util.random_encoded_bytes())],
  check_origin: System.get_env("CHECK_ORIGIN", "false") |> Util.parse_check_origin!()

if System.get_env("DISABLE_MQTT") != "true" do
  config :teslamate, :mqtt,
    host: System.fetch_env!("MQTT_HOST"),
    username: System.get_env("MQTT_USERNAME"),
    password: System.get_env("MQTT_PASSWORD"),
    tls: System.get_env("MQTT_TLS"),
    accept_invalid_certs: System.get_env("MQTT_TLS_ACCEPT_INVALID_CERTS")
end

config :logger,
  level: :info,
  compile_time_purge_matching: [[level_lower_than: :info]]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:car_id]

config :teslamate, :srtm_cache, System.get_env("SRTM_CACHE", ".srtm_cache")
