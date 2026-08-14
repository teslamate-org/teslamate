defmodule TestHelper do
  def eventually(fun, opts \\ []) do
    eventually(fun, Keyword.get(opts, :attempts, 10), Keyword.get(opts, :delay, 100))
  end

  defp eventually(fun, attempts, delay) do
    fun.()
  rescue
    e in [ExUnit.AssertionError] ->
      if attempts == 1, do: reraise(e, __STACKTRACE__)
      Process.sleep(delay)
      eventually(fun, attempts - 1, delay)
  end

  # Drains all Home Assistant discovery config messages published by
  # MqttPublisherMock, so they don't leak into subsequent assertions.
  def drain_discovery_configs do
    receive do
      {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, [retain: true, qos: 1]}} ->
        drain_discovery_configs()
    after
      200 -> :ok
    end
  end

  defmacro decimal(value) do
    value
    |> to_string()
    |> Decimal.new()
    |> Macro.escape()
  end
end
