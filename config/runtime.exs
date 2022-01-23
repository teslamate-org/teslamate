import Config

defmodule Util do
  def random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end

  def to_integer(nil), do: nil
  def to_integer(str), do: String.to_integer(str)

  def validate_namespace!(nil), do: nil
  def validate_namespace!(""), do: nil

  def validate_namespace!(ns) when is_binary(ns) do
    case String.contains?(ns, "/") do
      true -> raise "MQTT_NAMESPACE must not contain '/'"
      false -> ns
    end
  end

  def parse_check_origin!("true"), do: true
  def parse_check_origin!("false"), do: false
  def parse_check_origin!(hosts) when is_binary(hosts), do: String.split(hosts, ",")
  def parse_check_origin!(hosts), do: raise("Invalid check_origin option: #{inspect(hosts)}")

  def validate_import_dir(nil), do: nil

  def validate_import_dir(path) do
    path = Path.absname(path)

    case File.ls(path) do
      {:ok, [_ | _] = files} ->
        if Enum.any?(files, &TeslaMate.Import.valid_file_name?/1) do
          IO.puts("[info] Found #{length(files)} file(s) at '#{path}'. Starting in import mode!")
          path
        else
          nil
        end

      {:ok, []} ->
        nil

      {:error, :enoent} ->
        nil

      {:error, reason} ->
        IO.puts("[warn] Cannot access directory '#{path}': #{inspect(reason)}")
        nil
    end
  end

  def choose_http_binding_address() do
    defaults = [transport_options: [socket_opts: [:inet6]]]

    case System.get_env("HTTP_BINDING_ADDRESS", "") do
      "" ->
        defaults

      address ->
        case :inet.parse_address(to_charlist(address)) do
          {:ok, ip} ->
            [ip: ip]

          {:error, reason} ->
            IO.puts("Cannot parse HTTP_BINDING_ADDRESS '#{address}': #{inspect(reason)}")
            defaults
        end
    end
  end

  def fetch_env!(varname, defaults \\ []) do
    case config_env() do
      :prod -> System.fetch_env!(varname)
      env -> System.get_env(varname, defaults[env] || defaults[:all])
    end
  end

  def get_env(varname, defaults \\ []) do
    System.get_env(varname, defaults[config_env()])
  end
end

config :teslamate, TeslaMate.Repo,
  username: Util.fetch_env!("DATABASE_USER", all: "postgres"),
  password: Util.fetch_env!("DATABASE_PASS", all: "postgres"),
  database: Util.fetch_env!("DATABASE_NAME", dev: "teslamate_dev", test: "teslamate_test"),
  hostname: Util.fetch_env!("DATABASE_HOST", all: "localhost"),
  port: System.get_env("DATABASE_PORT", "5432"),
  ssl: System.get_env("DATABASE_SSL", "false") == "true",
  pool_size: System.get_env("DATABASE_POOL_SIZE", "10") |> String.to_integer(),
  timeout: System.get_env("DATABASE_TIMEOUT", "60000") |> String.to_integer()

if System.get_env("DATABASE_IPV6") == "true" do
  config :teslamate, TeslaMate.Repo, socket_options: [:inet6]
end

config :teslamate, TeslaMateWeb.Endpoint,
  http:
    Util.choose_http_binding_address() ++
      [port: Util.get_env("PORT", prod: "4000", dev: "4000", test: "4002")],
  url: [host: System.get_env("VIRTUAL_HOST", "localhost"), port: 80],
  secret_key_base: System.get_env("SECRET_KEY_BASE", Util.random_string(64)),
  live_view: [signing_salt: System.get_env("SIGNING_SALT", Util.random_string(8))],
  check_origin: System.get_env("CHECK_ORIGIN", "false") |> Util.parse_check_origin!()

if System.get_env("DISABLE_MQTT") != "true" or config_env() == :test do
  config :teslamate, :mqtt,
    host: Util.fetch_env!("MQTT_HOST", all: "localhost"),
    port: System.get_env("MQTT_PORT") |> Util.to_integer(),
    username: System.get_env("MQTT_USERNAME"),
    password: System.get_env("MQTT_PASSWORD"),
    tls: System.get_env("MQTT_TLS") == "true",
    accept_invalid_certs: System.get_env("MQTT_TLS_ACCEPT_INVALID_CERTS") == "true",
    namespace: System.get_env("MQTT_NAMESPACE") |> Util.validate_namespace!(),
    ipv6: System.get_env("MQTT_IPV6") == "true"
end

if config_env() != :test do
  config :teslamate,
    import_directory: System.get_env("IMPORT_DIR", "import") |> Util.validate_import_dir()
end

config :teslamate, :srtm_cache, System.get_env("SRTM_CACHE", ".srtm_cache")

config :teslamate, TeslaMate.Vault, key: Util.get_env("ENCRYPTION_KEY", test: "secret")
