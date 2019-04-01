defmodule TeslaMate.Vehicles.Vehicle.ChargingTest do
  use TeslaMate.VehicleCase, async: true

  defp charging_event(ts, charging_state, charger_power \\ nil) do
    vehicle_full(
      charge_state: %{
        timestamp: ts,
        charging_state: charging_state,
        charger_power: charger_power
      },
      drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0}
    )
  end

  @tag :only
  test "logs a full charging cycle", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging")},
      {:ok, charging_event(now_ts + 2, "Charging", 125)},
      {:ok, charging_event(now_ts + 3, "Charging", 120)},
      {:ok, charging_event(now_ts + 4, "Complete", 0)},
      {:ok, charging_event(now_ts + 5, "Complete")},
      {:ok, charging_event(now_ts + 6, "Unplugged")},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, 999, :online}

    assert_receive {:insert_position, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_charging_process, 999}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 125}}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 120}}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 0}}
    assert_receive {:close_charging_process, 99}

    assert_receive {:start_state, 999, :online}

    refute_receive _
  end

  @tag :capture_log
  test "handles a connection loss when charging", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging")},
      {:ok, charging_event(now_ts + 2, "Charging", 125)},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "unknown"}},
      {:ok, charging_event(now_ts + 3, "Charging", 120)},
      {:ok, charging_event(now_ts + 4, "Complete", 0)},
      {:ok, charging_event(now_ts + 5, "Complete")},
      {:ok, charging_event(now_ts + 6, "Unplugged")},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, 999, :online}

    assert_receive {:insert_position, 999, %{date: _, latitude: 0.0, longitude: 0.0, speed: nil}}
    assert_receive {:start_charging_process, 999}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 125}}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 120}}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 0}}
    assert_receive {:close_charging_process, 99}

    assert_receive {:start_state, 999, :online}

    refute_receive _
  end

  test "Transitions directly into charging state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, charging_event(now_ts, "Charging", 22)}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, 999, :online}

    assert_receive {:insert_position, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_charging_process, 999}

    assert_receive {:insert_charge, 99, %{date: _, charger_power: 22}}
    assert_receive {:insert_charge, 99, %{date: _, charger_power: 22}}
    # ...

    refute_received _
  end
end
