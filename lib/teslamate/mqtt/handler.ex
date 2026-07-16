defmodule TeslaMate.Mqtt.Handler do
  use Tortoise311.Handler

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.RuntimeHealth

  @impl true
  def connection(:up, state) do
    Logger.info("MQTT connection has been established")
    :ok = call(runtime_health(state), :record_mqtt_connection, [:up])
    {:ok, state}
  end

  def connection(:down, state) do
    Logger.warning("MQTT connection has been dropped")
    :ok = call(runtime_health(state), :record_mqtt_connection, [:down])
    {:ok, state}
  end

  def connection(:terminating, state) do
    Logger.warning("MQTT connection is terminating")
    :ok = call(runtime_health(state), :record_mqtt_connection, [:terminating])
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("MQTT Client has been terminated with reason: #{inspect(reason)}")
    :ok = call(runtime_health(state), :record_mqtt_connection, [:terminated])
    :ok
  end

  defp runtime_health(state) when is_list(state) do
    Keyword.get(state, :runtime_health, RuntimeHealth)
  end

  defp runtime_health(_state), do: RuntimeHealth
end
