defmodule TeslaMate.Vehicles.Vehicle.DrivingTest do
  use TeslaMate.VehicleCase, async: true

  test "logs a full drive", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts + 1, "D", 60)},
      {:ok, drive_event(now_ts + 2, "N", 30)},
      {:ok, drive_event(now_ts + 3, "R", -5)},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 97, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: ^s1}}}

    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: ^s1}}}

    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: -8, drive_id: 111}}
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  @tag :capture_log
  test "handles a connection loss when driving", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, drive_event(now_ts + 1, "D", 50)},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "unknown"}},
      {:ok, drive_event(now_ts + 2, "D", 55)},
      {:ok, drive_event(now_ts + 3, "D", 40)},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 80, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 89, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 64, drive_id: 111}}
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "transitions directly into driving state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "N", 0)}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, drive_id: 111}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, drive_id: 111}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, drive_id: 111}}
    # ...

    refute_received _
  end

  test "shift state P does not trigger driving state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "P", 0)}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "shift_state P ends the drive", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "D", 5)},
      {:ok, drive_event(now_ts, "D", 15)},
      {:ok, drive_event(now_ts, "P", 0)}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 8, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 24, drive_id: 111}}

    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  @tag :capture_log
  test "interprets a significant offline period while driving with SOC gains as charge session",
       %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    offline_events =
      for _ <- 1..20 do
        [
          {:error, :vehicle_unavailable},
          {:ok, %TeslaApi.Vehicle{state: "offline"}}
        ]
      end
      |> List.flatten()

    events =
      [
        {:ok, online_event()},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )}
      ] ++
        offline_events ++
        [
          {:ok,
           online_event(
             drive_state: %{
               timestamp: now_ts + :timer.minutes(5),
               latitude: 0.2,
               longitude: 0.2,
               shift_state: "D",
               speed: 20
             },
             charge_state: %{
               battery_level: 80,
               ideal_battery_range: 300,
               charge_energy_added: 45,
               timestamp: now_ts + :timer.minutes(5)
             }
           )},
          {:ok, online_event()}
        ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}

    refute_receive _, 200

    # Logs previous drive
    assert_receive {:close_drive, 111}

    # Logs a charge session based on the available data
    start_date = now |> DateTime.add(1, :second) |> DateTime.truncate(:second)
    end_date = now |> DateTime.add(5 * 60 - 1, :second) |> DateTime.truncate(:second)

    assert_receive {:start_charging_process, ^car_id, %{latitude: 0.1, longitude: 0.1},
                    date: ^start_date}

    assert_receive {:insert_charge, charging_id, %{date: _, charge_energy_added: nil}}
    assert_receive {:insert_charge, ^charging_id, %{date: _, charge_energy_added: 45}}

    assert_receive {:complete_charging_process, ^charging_id, [date: ^end_date]}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.2, speed: 32, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  @tag :capture_log
  test "logs a drive after a significant offline period while driving",
       %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    offline_events =
      for _ <- 1..20 do
        [
          {:error, :vehicle_unavailable},
          {:ok, %TeslaApi.Vehicle{state: "offline"}}
        ]
      end
      |> List.flatten()

    events =
      [
        {:ok, online_event()},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )}
      ] ++
        offline_events ++
        [
          {:ok,
           online_event(
             drive_state: %{
               timestamp: now_ts + :timer.minutes(15),
               latitude: 0.2,
               longitude: 0.2,
               shift_state: "D",
               speed: 20
             },
             charge_state: %{
               battery_level: 19,
               ideal_battery_range: 190,
               timestamp: now_ts + :timer.minutes(15)
             }
           )},
          {:ok, online_event()}
        ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}

    refute_receive _, 200

    # Logs previous drive
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.2, speed: 32, drive_id: 111}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  @tag :capture_log
  test "continues a drive after a short offline period while driving",
       %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    offline_events =
      for _ <- 1..20 do
        [
          {:error, :vehicle_unavailable},
          {:ok, %TeslaApi.Vehicle{state: "offline"}}
        ]
      end
      |> List.flatten()

    events =
      [
        {:ok, online_event()},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts,
             latitude: 0.1,
             longitude: 0.1,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{battery_level: 20, ideal_battery_range: 200, timestamp: now_ts}
         )}
      ] ++
        offline_events ++
        [
          {:ok,
           online_event(
             drive_state: %{
               timestamp: now_ts + :timer.minutes(4),
               latitude: 0.2,
               longitude: 0.2,
               shift_state: "D",
               speed: 20
             },
             charge_state: %{
               battery_level: 19,
               ideal_battery_range: 190,
               timestamp: now_ts + :timer.minutes(4)
             }
           )},
          {:ok, online_event()}
        ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, drive_id: 111}}

    refute_receive _, 200

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.2, speed: 32, drive_id: 111}}
    assert_receive {:close_drive, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end
end
