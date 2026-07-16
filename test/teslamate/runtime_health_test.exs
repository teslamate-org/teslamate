defmodule TeslaMate.RuntimeHealthTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Stream
  alias TeslaMate.RuntimeHealth

  setup context do
    {:ok, clock} = Agent.start_link(fn -> ~U[2026-07-16 10:00:00Z] end)
    name = {:global, {__MODULE__, context.test, self()}}

    start_supervised!(
      {RuntimeHealth,
       name: name,
       mqtt_enabled: true,
       clock: fn -> Agent.get(clock, & &1) end,
       stale_after: [summary: 60, api: 60, stream: 30],
       vehicle_expiry_seconds: 120}
    )

    {:ok, clock: clock, name: name}
  end

  test "reports an unavailable collector instead of a healthy empty state" do
    missing = {:global, {__MODULE__, :missing, self()}}
    assert {:error, :unavailable} = RuntimeHealth.report(missing)
    assert {:error, :unavailable} = RuntimeHealth.public_report(missing)
  end

  test "tracks normalized API results without retaining raw payloads", %{clock: clock, name: name} do
    :ok = RuntimeHealth.record_api(name, 7, {:ok, %{private: "not stored"}})

    assert %{vehicles: [%{api: api}]} = RuntimeHealth.report(name)
    assert api.status == :ok
    assert api.last_success_at == "2026-07-16T10:00:00Z"
    assert api.consecutive_failures == 0
    refute inspect(RuntimeHealth.snapshot(name)) =~ "not stored"

    set_clock(clock, ~U[2026-07-16 10:00:10Z])
    :ok = RuntimeHealth.record_api(name, 7, {:error, :too_many_request, 30})

    assert %{vehicles: [%{api: api}]} = RuntimeHealth.report(name)
    assert api.status == :degraded
    assert api.reason == :rate_limited
    assert api.retry_at == "2026-07-16T10:00:40Z"
    assert api.consecutive_failures == 1

    :ok = RuntimeHealth.record_api(name, 7, {:error, {:secret, "never expose me"}})
    :ok = RuntimeHealth.record_api(name, 7, {:error, :timeout})

    assert %{status: :degraded, vehicles: [%{api: api}]} = RuntimeHealth.report(name)
    assert api.status == :down
    assert api.reason == :timeout
    refute inspect(RuntimeHealth.snapshot(name)) =~ "never expose me"

    :ok = RuntimeHealth.record_api(name, 7, {:error, :vehicle_unavailable})

    assert %{vehicles: [%{api: %{status: :idle, reason: :vehicle_unavailable}}]} =
             RuntimeHealth.report(name)
  end

  test "stores stream timing but not position data", %{clock: clock, name: name} do
    :ok = RuntimeHealth.record_stream(name, 2, {:liveness, :connected})

    assert %{vehicles: [%{stream: stream}]} = RuntimeHealth.report(name)
    assert stream.status == :idle
    assert stream.reason == :waiting_for_data

    set_clock(clock, ~U[2026-07-16 10:00:20Z])

    event = %Stream.Data{
      time: ~U[2026-07-16 10:00:15Z],
      est_lat: 12.3456789,
      est_lng: 98.7654321
    }

    :ok = RuntimeHealth.record_stream(name, 2, event)

    assert %{vehicles: [%{stream: stream}]} = RuntimeHealth.report(name)
    assert stream.status == :ok
    assert stream.last_event_at == "2026-07-16T10:00:15Z"
    assert stream.data_age_seconds == 5
    refute inspect(RuntimeHealth.snapshot(name)) =~ "12.3456789"
    refute inspect(RuntimeHealth.snapshot(name)) =~ "98.7654321"

    :ok = RuntimeHealth.record_stream(name, 2, :inactive)

    assert %{vehicles: [%{stream: %{status: :idle, reason: :inactive}}]} =
             RuntimeHealth.report(name)

    :ok = RuntimeHealth.record_stream(name, 2, :tokens_expired)

    assert %{vehicles: [%{stream: %{status: :down, reason: :tokens_expired}}]} =
             RuntimeHealth.report(name)
  end

  test "uses unique MQTT generations and broadcasts only reconnects", %{name: name} do
    :ok = RuntimeHealth.subscribe_mqtt(name)
    initial_generation = RuntimeHealth.mqtt_generation(name)

    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    assert %{mqtt: %{status: :ok}} = RuntimeHealth.report(name)
    assert RuntimeHealth.mqtt_generation(name) == initial_generation
    refute_receive {:mqtt_reconnected, _}

    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    _report = RuntimeHealth.report(name)
    assert RuntimeHealth.mqtt_generation(name) == initial_generation
    refute_receive {:mqtt_reconnected, _}

    :ok = RuntimeHealth.record_mqtt_connection(name, :down)
    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    _report = RuntimeHealth.report(name)

    reconnect_generation = RuntimeHealth.mqtt_generation(name)
    refute reconnect_generation == initial_generation
    assert_receive {:mqtt_reconnected, ^reconnect_generation}

    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    _report = RuntimeHealth.report(name)
    assert RuntimeHealth.mqtt_generation(name) == reconnect_generation
    refute_receive {:mqtt_reconnected, _}
  end

  test "changes the MQTT generation when the collector restarts", %{name: name} do
    old_pid = GenServer.whereis(name)
    old_generation = RuntimeHealth.mqtt_generation(name)

    Process.exit(old_pid, :kill)
    new_pid = wait_for_restart(name, old_pid)

    refute new_pid == old_pid
    refute RuntimeHealth.mqtt_generation(name) == old_generation
  end

  test "keeps logger, API, stream and MQTT health independent", %{name: name} do
    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    :ok = RuntimeHealth.record_summary(name, 9, {:driving, :available, 123})
    :ok = RuntimeHealth.record_api(name, 9, {:ok, :vehicle})
    :ok = RuntimeHealth.record_stream(name, 9, :inactive)
    :ok = RuntimeHealth.record_mqtt_publish(name, 9, {:error, :disconnected})

    assert %{
             status: :degraded,
             vehicles: [
               %{
                 logger_state: :driving,
                 logger: %{status: :ok},
                 api: %{status: :ok},
                 stream: %{status: :idle},
                 mqtt: %{status: :degraded, reason: :publish_failed}
               }
             ]
           } = RuntimeHealth.report(name)
  end

  test "derives stale and unknown expected health at report time", %{clock: clock, name: name} do
    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    :ok = RuntimeHealth.record_summary(name, 11, :driving)

    assert %{status: :degraded, vehicles: [%{api: %{reason: :no_signal}}]} =
             RuntimeHealth.report(name)

    :ok = RuntimeHealth.record_api(name, 11, {:ok, :vehicle})
    :ok = RuntimeHealth.record_stream(name, 11, {:liveness, :connected})
    :ok = RuntimeHealth.record_mqtt_publish(name, 11, :ok)

    assert %{status: :ok, vehicles: [%{status: :ok}]} = RuntimeHealth.report(name)

    set_clock(clock, ~U[2026-07-16 10:00:31Z])

    assert %{status: :degraded, vehicles: [%{stream: %{reason: :stale}}]} =
             RuntimeHealth.report(name)

    set_clock(clock, ~U[2026-07-16 10:01:01Z])

    assert %{
             status: :degraded,
             vehicles: [%{logger: %{reason: :stale}, api: %{reason: :stale}}]
           } = RuntimeHealth.report(name)
  end

  test "public report contains aggregate status only", %{name: name} do
    :ok = RuntimeHealth.record_mqtt_connection(name, :up)
    :ok = RuntimeHealth.record_summary(name, 91, :driving)
    :ok = RuntimeHealth.record_api(name, 91, {:ok, :vehicle})
    :ok = RuntimeHealth.record_stream(name, 91, :inactive)
    :ok = RuntimeHealth.record_mqtt_publish(name, 91, :ok)

    assert {:ok,
            %{
              schema_version: 1,
              status: :ok,
              mqtt: %{status: :ok},
              vehicles: %{total: 1, ok: 1, degraded: 0}
            } = report} = RuntimeHealth.public_report(name)

    encoded = Jason.encode!(report)
    refute encoded =~ "car_id"
    refute encoded =~ "driving"
    refute encoded =~ "generated_at"
    refute encoded =~ "last_"
  end

  test "removes stopped and expired vehicles", %{clock: clock, name: name} do
    :ok = RuntimeHealth.record_summary(name, 21, :online)
    assert %{vehicles: [%{car_id: 21}]} = RuntimeHealth.report(name)

    :ok = RuntimeHealth.remove_vehicle(name, 21)
    assert %{vehicles: []} = RuntimeHealth.report(name)

    :ok = RuntimeHealth.record_summary(name, 22, :online)
    assert %{vehicles: [%{car_id: 22}]} = RuntimeHealth.report(name)
    set_clock(clock, ~U[2026-07-16 10:02:01Z])
    assert %{vehicles: []} = RuntimeHealth.report(name)
  end

  defp set_clock(clock, datetime), do: Agent.update(clock, fn _ -> datetime end)

  defp wait_for_restart(name, old_pid, attempts \\ 100)

  defp wait_for_restart(_name, _old_pid, 0), do: flunk("RuntimeHealth did not restart")

  defp wait_for_restart(name, old_pid, attempts) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _other ->
        Process.sleep(10)
        wait_for_restart(name, old_pid, attempts - 1)
    end
  end
end
