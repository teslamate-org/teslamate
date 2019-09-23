defmodule TeslaMate.Vehicles.Vehicle.ChargingTest do
  use TeslaMate.VehicleCase, async: true

  test "logs a full charging cycle", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Starting", 0.1, range: 1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2, range: 2)},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3, range: 3)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.4, range: 4)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.4, range: 4)},
      {:ok, charging_event(now_ts + 6, "Unplugged", 0.4, range: 4)},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0},
                    []}

    assert_receive {:insert_charge, charging_id,
                    %{
                      date: _,
                      charge_energy_added: 0.1,
                      rated_battery_range_km: 1.6,
                      ideal_battery_range_km: 1.6
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:insert_charge, ^charging_id,
                    %{
                      date: _,
                      charge_energy_added: 0.2,
                      rated_battery_range_km: 3.2,
                      ideal_battery_range_km: 3.2
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: ^s1}}}

    assert_receive {:insert_charge, ^charging_id,
                    %{
                      date: _,
                      charge_energy_added: 0.3,
                      rated_battery_range_km: 4.8,
                      ideal_battery_range_km: 4.8
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: ^s1}}}

    assert_receive {:insert_charge, ^charging_id,
                    %{
                      date: _,
                      charge_energy_added: 0.4,
                      rated_battery_range_km: 6.4,
                      ideal_battery_range_km: 6.4
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging_complete, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    # Completed
    assert_receive {:complete_charging_process, ^charging_id, []}
    # Unplugged
    assert_receive {:complete_charging_process, ^charging_id, []}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s3}}}
    assert DateTime.diff(s2, s3, :nanosecond) < 0

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: ^s3}}}

    refute_receive _
  end

  @tag :capture_log
  test "handles a connection loss when charging", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2)},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "unknown"}},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 6, "Unplugged", 0.3)},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0},
                    []}

    assert_receive {:insert_charge, charging_id, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^charging_id, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^charging_id, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^charging_id, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging_complete}}}
    assert_receive {:complete_charging_process, ^charging_id, []}

    assert_receive {:complete_charging_process, ^charging_id, []}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "Transitions directly into charging state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts, "Charging", 22)}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0},
                    []}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, charging_event, %{date: _, charge_energy_added: 22}}
    assert_receive {:insert_charge, ^charging_event, %{date: _, charge_energy_added: 22}}
    # ...

    refute_received _
  end
end
