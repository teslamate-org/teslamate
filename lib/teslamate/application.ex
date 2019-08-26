defmodule TeslaMate.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    [
      TeslaMate.Repo,
      TeslaMate.Api,
      TeslaMateWeb.Endpoint,
      TeslaMate.Mapping,
      TeslaMate.Vehicles,
      if(mqtt_enabled?(), do: TeslaMate.Mqtt)
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
