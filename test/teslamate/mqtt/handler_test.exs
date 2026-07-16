defmodule TeslaMate.Mqtt.HandlerTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Mqtt.Handler
  alias TeslaMate.RuntimeHealth

  test "records broker connection state without exposing termination details", context do
    name = {:global, {__MODULE__, context.test, self()}}
    start_supervised!({RuntimeHealth, name: name, mqtt_enabled: true})
    state = [runtime_health: {RuntimeHealth, name}]

    assert {:ok, ^state} = Handler.connection(:up, state)
    assert %{mqtt: %{status: :ok}} = RuntimeHealth.report(name)

    assert {:ok, ^state} = Handler.connection(:down, state)
    assert %{mqtt: %{status: :degraded, reason: :broker_down}} = RuntimeHealth.report(name)

    assert :ok = Handler.terminate({:secret, "not public"}, state)
    report = RuntimeHealth.report(name)
    assert report.mqtt.status == :down
    assert report.mqtt.reason == :client_terminated
    refute Jason.encode!(report) =~ "not public"
  end
end
