defmodule TeslaMate.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      TeslaMate.Repo,
      TeslaMateWeb.Endpoint,
      TeslaMateWeb.Presence,
      {TeslaMate.Api, auth()},
      TeslaMate.Vehicles,
      TeslaMate.Mqtt
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TeslaMate.Supervisor)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TeslaMateWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp auth do
    Application.get_env(:teslamate, :tesla_auth)
  end
end
