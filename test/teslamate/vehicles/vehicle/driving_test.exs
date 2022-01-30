defmodule TeslaMate.Vehicles.Vehicle.DrivingTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.Drive

  test "logs a full drive", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts + 1, "D", 60)},
      {:ok, drive_event(now_ts + 2, "N", 30)},
      {:ok, drive_event(now_ts + 3, "R", -5)},
      {:ok, online_event(drive_state: %{timestamp: now_ts + 4, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts + 1, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 97}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: ^s1}}}

    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, since: ^s1}}}

    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: -8}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.2}}
    assert_receive {:close_drive, ^drive, lookup_address: true}

    start_date = DateTime.from_unix!(now_ts + 4, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {:insert_position, ^car, %{}}
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
      {:ok, online_event(drive_state: %{timestamp: now_ts + 4, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 80}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 89}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 64}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.2}}
    assert_receive {:close_drive, ^drive, lookup_address: true}

    start_date = DateTime.from_unix!(now_ts + 4, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  @tag :capture_log
  test "handles an empty drive_state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts + 0, "D", 5)},
      {:ok, drive_event(now_ts + 1, "D", 50)},
      {:ok, %TeslaApi.Vehicle{state: "online", drive_state: nil}},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, _drive, %{longitude: 0.1, speed: 8}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, _drive, %{longitude: 0.1, speed: 80}}

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

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 0}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 0}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 0}}

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

    date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  test "shift_state P ends the drive", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "D", 5)},
      {:ok, drive_event(now_ts + 1, "D", 15)},
      {:ok, drive_event(now_ts + 2, "P", 0)}
    ]

    :ok = start_vehicle(name, events)

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car, :online, date: ^start_date}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, %Drive{id: 111} = drive, %{longitude: 0.1, speed: 8}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 24}}
    assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 0}}
    assert_receive {:close_drive, ^drive, lookup_address: true}

    start_date = DateTime.from_unix!(now_ts + 2, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^start_date}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    refute_receive _
  end

  describe "when offline" do
    defp drive_event(ts, pos, speed, lvl, range, added) do
      {:ok,
       online_event(
         drive_state: %{
           timestamp: ts,
           latitude: pos,
           longitude: pos,
           shift_state: "D",
           speed: speed
         },
         charge_state: %{
           battery_level: lvl,
           ideal_battery_range: range,
           timestamp: ts,
           charge_energy_added: added
         }
       )}
    end

    @tag :capture_log
    test "interprets a significant offline period while driving with SOC gains as charge session",
         %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events =
        [
          {:ok, online_event()},
          drive_event(now_ts, 0.1, 30, 20, 200, 0),
          drive_event(now_ts + 1, 0.1, 30, 20, 200, 0)
        ] ++
          List.duplicate({:ok, %TeslaApi.Vehicle{state: "offline"}}, 20) ++
          [
            drive_event(now_ts + :timer.minutes(5), 0.2, 20, 80, 300, 45),
            {:ok,
             online_event(
               drive_state: %{
                 timestamp: now_ts + :timer.minutes(5) + 1,
                 latitude: 0.3,
                 longitude: 0.3
               }
             )}
          ]

      :ok = start_vehicle(name, events)

      date = DateTime.from_unix!(now_ts, :millisecond)
      assert_receive {:start_state, car, :online, date: ^date}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 48}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}

      refute_receive _, 50
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :offline}}}

      # Logs previous drive because of timeout
      assert_receive {:close_drive, ^drive, lookup_address: true}, 300

      # Logs a charge session based on the available data
      start_date =
        now
        |> DateTime.add(1, :millisecond)
        |> DateTime.truncate(:millisecond)

      end_date =
        now
        |> DateTime.add(5 * 60, :second)
        |> DateTime.truncate(:millisecond)

      assert_receive {:start_charging_process, ^car, %{latitude: 0.1, longitude: 0.1},
                      lookup_address: true}

      assert_receive {:insert_charge, charging_id,
                      %{date: ^start_date, charge_energy_added: 0, charger_power: 0}}

      assert_receive {:insert_charge, ^charging_id,
                      %{date: ^end_date, charge_energy_added: 45, charger_power: 0}}

      assert_receive {:complete_charging_process, ^charging_id}

      d1 = DateTime.from_unix!(now_ts + :timer.minutes(5), :millisecond)
      assert_receive {:start_state, ^car, :online, date: ^d1}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.2, speed: 32}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.3}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      d2 = DateTime.from_unix!(now_ts + :timer.minutes(5) + 1, :millisecond)
      assert_receive {:start_state, ^car, :online, date: ^d2}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    @tag :capture_log
    test "times out a drive when being offline for to long",
         %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      events = [
        {:ok, online_event()},
        drive_event(now_ts, 0.1, 30, 20, 200, nil),
        drive_event(now_ts, 0.1, 30, 20, 200, nil),
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, events)

      date = DateTime.from_unix!(now_ts, :millisecond)
      assert_receive {:start_state, car, :online, date: ^date}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 48}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}

      # Timeout
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :offline}}}, 200
      assert_receive {:close_drive, ^drive, lookup_address: true}, 1200

      refute_receive _
    end

    test "times out a drive when rececing sleep event", %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      events = [
        {:ok, online_event()},
        drive_event(now_ts, 0.1, 30, 20, 200, nil),
        drive_event(now_ts + 1, 0.1, 30, 20, 200, nil),
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)

      date = DateTime.from_unix!(now_ts, :millisecond)
      assert_receive {:start_state, car, :online, date: ^date}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 48}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}

      # Timeout
      assert_receive {:close_drive, ^drive, lookup_address: true}, 1200
      assert_receive {:start_state, _car, :asleep, []}
      assert_receive {:"$websockex_cast", :disconnect}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

      refute_receive _
    end

    @tag :capture_log
    test "logs a drive after a significant offline period while driving",
         %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events =
        [
          {:ok, online_event()},
          drive_event(now_ts, 0.1, 30, 20, 200, nil),
          drive_event(now_ts + 1, 0.1, 30, 20, 200, nil)
        ] ++
          List.duplicate({:ok, %TeslaApi.Vehicle{state: "offline"}}, 20) ++
          [
            drive_event(now_ts + :timer.minutes(15), 0.2, 20, 19, 190, nil),
            {:ok,
             online_event(
               drive_state: %{
                 timestamp: now_ts + :timer.minutes(15) + 1,
                 latitude: 0.3,
                 longitude: 0.3
               }
             )}
          ]

      :ok = start_vehicle(name, events)

      d0 = DateTime.from_unix!(now_ts, :millisecond)
      assert_receive {:start_state, car, :online, date: ^d0}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 48}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}

      refute_receive _, 100
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :offline}}}

      # Logs previous drive
      assert_receive {:close_drive, ^drive, lookup_address: true}, 250

      d1 = DateTime.from_unix!(now_ts + :timer.minutes(15), :millisecond)
      assert_receive {:start_state, ^car, :online, date: ^d1}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, _drive, %{longitude: 0.2, speed: 32}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
      assert_receive {:insert_position, drive, %{longitude: 0.3}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      d2 = DateTime.from_unix!(now_ts + :timer.minutes(15) + 1, :millisecond)
      assert_receive {:start_state, ^car, :online, date: ^d2}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    @tag :capture_log
    test "continues a drive after a short offline period while driving",
         %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events =
        [
          {:ok, online_event()},
          drive_event(now_ts, 0.1, 30, 20, 200, nil),
          drive_event(now_ts + 1, 0.1, 30, 20, 200, nil)
        ] ++
          List.duplicate({:ok, %TeslaApi.Vehicle{state: "offline"}}, 16) ++
          [
            drive_event(now_ts + :timer.minutes(4), 0.2, 20, 19, 190, nil),
            {:ok,
             online_event(
               drive_state: %{
                 timestamp: now_ts + :timer.minutes(4) + 1,
                 latitude: 0.3,
                 longitude: 0.3
               }
             )}
          ]

      :ok = start_vehicle(name, events)

      d0 = DateTime.from_unix!(now_ts, :millisecond)
      assert_receive {:start_state, car, :online, date: ^d0}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 48}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 48}}

      refute_receive _, 50

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
      assert_receive {:insert_position, drive, %{longitude: 0.2, speed: 32}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.3}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      d1 = DateTime.from_unix!(now_ts + :timer.minutes(4) + 1, :millisecond)
      assert_receive {:start_state, ^car, :online, date: ^d1}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end

  describe "geofencing" do
    alias TeslaMate.Locations.GeoFence

    test "changes geofence when enterling or leaving", %{test: name} do
      ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      drive_event = fn s, lat, lng ->
        online_event(drive_state: %{timestamp: ts, shift_state: s, latitude: lat, longitude: lng})
      end

      events = [
        {:ok, online_event()},
        {:ok, drive_event.("D", 90, 45)},
        {:ok, drive_event.("D", 90, 45.1)},
        {:ok, drive_event.("D", 90, 45.2)},
        {:ok, drive_event.("D", 90, 45.1)},
        {:ok, drive_event.("P", 90, 45)}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{longitude: 45}}

      assert_receive {:pubsub,
                      {:broadcast, _, _,
                       %Summary{state: :online, geofence: %GeoFence{name: "South Pole"}}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 45}}

      assert_receive {:pubsub,
                      {:broadcast, _, _,
                       %Summary{state: :driving, geofence: %GeoFence{name: "South Pole"}}}}

      assert_receive {:insert_position, ^drive, %{longitude: 45.1}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, geofence: nil}}}

      assert_receive {:insert_position, ^drive, %{longitude: 45.2}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, geofence: nil}}}

      assert_receive {:insert_position, ^drive, %{longitude: 45.1}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, geofence: nil}}}

      assert_receive {:insert_position, ^drive, %{longitude: 45}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      assert_receive {:start_state, ^car, :online, date: _}
      assert_receive {:insert_position, ^car, %{longitude: 45}}

      assert_receive {:pubsub,
                      {:broadcast, _, _,
                       %Summary{state: :online, geofence: %GeoFence{name: "South Pole"}}}}

      refute_receive _
    end
  end
end
