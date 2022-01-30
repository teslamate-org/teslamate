defmodule TeslaMate.Vehicles.Vehicle.ChargingTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.ChargingProcess

  import ExUnit.CaptureLog

  @log_opts format: "[$level] $message\n",
            colors: [enabled: false]

  test "logs a full charging cycle", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Starting", 0.1, range: 1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2, range: 2)},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3, range: 3)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.4, range: 4)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.4, range: 4)},
      {:ok, charging_event(now_ts + 6, "Unplugged", 0.4, range: 4)},
      {:ok, online_event(drive_state: %{timestamp: now_ts + 7, latitude: 0.2, longitude: 0.2})},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}, 400
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}

    assert_receive {:insert_charge, %ChargingProcess{id: _process_id} = cproc,
                    %{
                      date: _,
                      charge_energy_added: 0.1,
                      rated_battery_range_km: 1.61,
                      ideal_battery_range_km: 1.61
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:insert_charge, ^cproc,
                    %{
                      date: _,
                      charge_energy_added: 0.2,
                      rated_battery_range_km: 3.22,
                      ideal_battery_range_km: 3.22
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: ^s1}}}

    assert_receive {:insert_charge, ^cproc,
                    %{
                      date: _,
                      charge_energy_added: 0.3,
                      rated_battery_range_km: 4.83,
                      ideal_battery_range_km: 4.83
                    }}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging, since: ^s1}}}

    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:insert_charge, ^cproc,
                    %{
                      date: _,
                      charge_energy_added: 0.4,
                      rated_battery_range_km: 6.44,
                      ideal_battery_range_km: 6.44
                    }}

    # Completed
    assert_receive {:complete_charging_process, ^cproc}

    start_date = DateTime.from_unix!(now_ts + 4, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: ^s2}}}

    refute_receive _
  end

  @tag :capture_log
  test "handles a connection loss when charging", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

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
      {:ok, online_event(drive_state: %{timestamp: now_ts + 7, latitude: 0.2, longitude: 0.2})},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}

    assert_receive {:insert_charge, %ChargingProcess{id: _cproc_id} = cproc,
                    %{date: _, charge_energy_added: 0.1}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:complete_charging_process, ^cproc}

    start_date = DateTime.from_unix!(now_ts + 4, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "handles a invalid charge data", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, %TeslaApi.Vehicle{state: "online", charge_state: nil}},
      {:ok, %TeslaApi.Vehicle{state: "online", charge_state: nil}},
      {:ok, %TeslaApi.Vehicle{state: "online", charge_state: nil}},
      {:ok, charging_event(now_ts + 3, "Charging", 0.3)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.3)},
      {:ok, online_event(drive_state: %{timestamp: now_ts + 6, latitude: 0.2, longitude: 0.2})},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}

    assert_receive {:insert_charge, cproc, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert capture_log(@log_opts, fn ->
             assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.3}}
             assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
           end) =~ "Discarded incomplete fetch result"

    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:complete_charging_process, ^cproc}

    start_date = DateTime.from_unix!(now_ts + 5, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "Transitions directly into charging state", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts, "Charging", 22)},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:insert_charge, _charging_event, %{date: _, charge_energy_added: 22}}

    refute_received _
  end

  @tag :capture_log
  test "transisitions into asleep state", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Charging", 0.2)},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}

    assert_receive {:insert_charge, %ChargingProcess{id: _cproc_id} = cproc,
                    %{date: _, charge_energy_added: 0.1}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:complete_charging_process, ^cproc}
    assert_receive {:start_state, ^car, :asleep, []}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

    refute_receive _
  end
end
