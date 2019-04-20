use Mix.Config

defmodule Env do
  def get(key), do: System.get_env(key)
  def get_boolean(key), do: key |> get() |> parse_boolean()
  def get_integer(key, default \\ 0), do: key |> get() |> parse_integer(default)
  def exists?(key), do: get(key) not in [nil, ""]

  defp parse_boolean("true"), do: true
  defp parse_boolean("1"), do: true
  defp parse_boolean(_), do: false

  defp parse_integer(value, _) when is_bitstring(value), do: String.to_integer(value)
  defp parse_integer(_, default), do: default
end

config :teslamate, TeslaMate.Repo,
  username: Env.get("DATABASE_USER"),
  password: Env.get("DATABASE_PASS"),
  database: Env.get("DATABASE_NAME"),
  hostname: Env.get("DATABASE_HOST"),
  pool_size: 15

config :teslamate, TeslaMateWeb.Endpoint,
  http: [:inet6, port: Env.get_integer("PORT", 4000)],
  url: [host: Env.get("VIRTUAL_HOST"), port: 80],
  secret_key_base: Env.get("SECRET_KEY_BASE"),
  live_view: [
    signing_salt: Env.get("SIGNING_SALT")
  ]

config :teslamate, :tesla_auth,
  username: Env.get("TESLA_USERNAME"),
  password: Env.get("TESLA_PASSWORD")

config :teslamate, :mqtt,
  host: Env.get("MQTT_HOST"),
  username: Env.get("MQTT_USERNAME"),
  password: Env.get("MQTT_PASSWORD")

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
  chat_id: Env.get("CHAT_ID"),
  token: Env.get("TOKEN")

config :teslamate, :mqtt,
  host: Env.get("MQTT_HOST"),
  username: Env.get("MQTT_USERNAME"),
  password: Env.get("MQTT_PASSWORD")
