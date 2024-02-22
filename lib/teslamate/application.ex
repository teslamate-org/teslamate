defmodule TeslaMate.Application do
  use Application

  require Logger

  def start(_type, _args) do
    Logger.info("System Info: #{system_info()}")
    Logger.info("Version: #{Application.spec(:teslamate, :vsn) || "???"}")

    # Disable log entries
    :ok = :telemetry.detach({Phoenix.Logger, [:phoenix, :socket_connected]})
    :ok = :telemetry.detach({Phoenix.Logger, [:phoenix, :channel_joined]})

    Supervisor.start_link(children(), strategy: :one_for_one, name: TeslaMate.Supervisor)
  end

  defp children do
    mqtt_config = Application.get_env(:teslamate, :mqtt)

    case Application.get_env(:teslamate, :import_directory) do
      nil ->
        [
          TeslaMate.Repo,
          TeslaMate.Vault,
          TeslaMate.HTTP,
          TeslaMate.Api,
          TeslaMate.Updater,
          {Phoenix.PubSub, name: TeslaMate.PubSub},
          TeslaMateWeb.Endpoint,
          TeslaMate.Terrain,
          TeslaMate.Vehicles,
          if(mqtt_config != nil, do: {TeslaMate.Mqtt, mqtt_config}),
          TeslaMate.Repair
        ]
        |> Enum.reject(&is_nil/1)

      import_directory ->
        [
          TeslaMate.Repo,
          TeslaMate.Vault,
          TeslaMate.HTTP,
          TeslaMate.Api,
          TeslaMate.Updater,
          {Phoenix.PubSub, name: TeslaMate.PubSub},
          TeslaMateWeb.Endpoint,
          {TeslaMate.Terrain, disabled: true},
          {TeslaMate.Repair, limit: 250},
          {TeslaMate.Import, directory: import_directory}
        ]
    end
  end

  defp system_info do
    case otp_release() do
      vsn when vsn <= 23 -> "Erlang/OTP #{vsn}"
      vsn -> "Erlang/OTP #{vsn} (#{emu_flavor()})"
    end
  end

  defp otp_release do
    :erlang.system_info(:otp_release) |> to_string() |> String.to_integer()
  rescue
    _ -> nil
  end

  defp emu_flavor do
    :erlang.system_info(:emu_flavor)
  rescue
    ArgumentError -> nil
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TeslaMateWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
