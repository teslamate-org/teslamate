defmodule TeslaMate.Application do
  use Application

  require Logger

  def start(_type, _args) do
    Logger.info("Version: #{Application.spec(:teslamate, :vsn) || "???"}")

    [
      TeslaMate.Repo,
      TeslaMate.Api,
      TeslaMate.Locations,
      TeslaMateWeb.Endpoint,
      TeslaMate.Terrain,
      TeslaMate.Vehicles,
      if(mqtt_enabled?(), do: TeslaMate.Mqtt),
      TeslaMate.Repair
    ]
    |> Enum.reject(&is_nil/1)
    |> Supervisor.start_link(strategy: :one_for_one, name: TeslaMate.Supervisor)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TeslaMateWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp mqtt_enabled?, do: !is_nil(Application.get_env(:teslamate, :mqtt))
end
