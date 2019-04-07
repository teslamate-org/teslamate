defmodule TeslaMate.Vehicles.Vehicle.ChargingTest do
  use TeslaMate.VehicleCase, async: true

  test "logs a full charging cycle", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.4)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.4)},
      {:ok, charging_event(now_ts + 6, "Unplugged", 0.4)},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, 999, :online}

    assert_receive {:start_charging_process, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.4}}
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
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2)},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "unknown"}},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 6, "Unplugged", 0.3)},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, 999, :online}

    assert_receive {:start_charging_process, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.3}}
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

    assert_receive {:start_charging_process, 999, %{date: _, latitude: 0.0, longitude: 0.0}}

    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 22}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 22}}
    # ...

    refute_received _
  end
end
