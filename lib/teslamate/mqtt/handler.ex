defmodule TeslaMate.Mqtt.Handler do
  use Tortoise.Handler

  require Logger

  @impl true
  def connection(:up, state) do
    Logger.info("MQTT connection has been established")
    {:ok, state}
  end

  def connection(:down, state) do
    Logger.warning("MQTT connection has been dropped")
    {:ok, state}
  end

  def connection(:terminating, state) do
    Logger.warning("MQTT connection is terminating")
    {:ok, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("MQTT Client has been terminated with reason: #{inspect(reason)}")
    :ok
  end
end
