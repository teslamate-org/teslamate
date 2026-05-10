defmodule TeslaMate.HealthCheck do
  @moduledoc """
  A GenServer that periodically pings a health check URL every 10 minutes.
  """

  use GenServer
  require Logger

  @name __MODULE__
  @ping_url "https://hc-ping.com/2d5316dd-9c01-45c6-aca8-f85d0f17d767"
  @ping_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @impl GenServer
  def init(_opts) do
    # Start the ping interval timer
    {:ok, _} = :timer.send_interval(@ping_interval, :ping)

    # Send initial ping immediately
    Process.send_after(self(), :ping, 1000)

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:ping, state) do
    Logger.debug("Sending health check ping to #{@ping_url}")

    case TeslaMate.HTTP.post(@ping_url, "") do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        Logger.debug("Health check ping successful (status: #{status})")

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("Health check ping failed with status: #{status}")

      {:error, reason} ->
        Logger.warning("Health check ping failed: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
