defmodule TeslaMate.Vehicles.Vehicle.StreamingTest do
  use TeslaMate.VehicleCase, async: true

  import ExUnit.CaptureLog

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaApi.Stream

  defp stream(name, data) do
    base_attrs = %{
      shift_state: nil,
      est_lat: 42.10,
      est_lng: 42.00,
      speed: 0,
      odometer: 1000,
      elevation: 10,
      est_heading: 120,
      est_range: 200,
      range: 180,
      heading: 300,
      power: 0,
      soc: 60,
      time: nil
    }

    send(name, {:stream, struct!(Stream.Data, Map.merge(base_attrs, data))})
  end

  describe "driving" do
    @log_opts format: "[$level] $message
",
              colors: [enabled: false]

    @tag :capture_log
    test "starts a drive", %{test: name} do
      me = self()
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, online_event()},
        {:ok, online_event(drive_state: %{timestamp: now_ts})},
        fn ->
          send(me, :continue?)

          receive do
            :continue -> {:error, :closed}
          after
            5_000 -> raise "No :continue after 5s"
          end
        end,
        {:error, :closed},
        {:error, :closed},
        {:error, :closed},
        {:error, :closed},
        {:ok,
         online_event(
           drive_state: %{
             timestamp: now_ts + 10,
             latitude: 42.91,
             longitude: 42.81,
             shift_state: "P",
             speed: 0,
             power: 0
           }
         )},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert_receive :continue?
      stream(name, %{shift_state: "P", time: now})
      refute_receive _

      stream(name, %{shift_state: "D", speed: 10, power: 5, elevation: 1, time: now})
      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, position}

      assert_receive {:pubsub,
                      {:broadcast, _, _,
                       %Summary{state: :driving, speed: 16, power: 5, elevation: 1}}}

      assert position == %{
               latitude: 42.1,
               longitude: 42.0,
               speed: 16,
               battery_level: 60,
               date: now,
               elevation: 1,
               odometer: 1609.344,
               power: 5
             }

      stream(name, %{
        shift_state: "D",
        speed: 15,
        power: 10,
        est_lat: 42.31,
        elevation: 2,
        time: now
      })

      assert_receive {:insert_position, ^drive,
                      %{speed: 24, power: 10, latitude: 42.31, elevation: 2}}

      assert_receive {:pubsub,
                      {:broadcast, _, _, %Summary{state: :driving, speed: 24, power: 10}}}

      stream(name, %{
        shift_state: "N",
        speed: 20,
        power: 2,
        est_lat: 42.32,
        elevation: 3,
        time: now
      })

      assert_receive {:insert_position, ^drive,
                      %{speed: 32, power: 2, latitude: 42.32, elevation: 3}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, speed: 32, power: 2}}}

      stream(name, %{
        shift_state: "R",
        speed: 3,
        power: 1,
        est_lat: 42.33,
        elevation: 4,
        time: now
      })

      assert_receive {:insert_position, ^drive,
                      %{speed: 5, power: 1, latitude: 42.33, elevation: 4}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, speed: 5, power: 1}}}

      send(:"api_#{name}", :continue)
      stream(name, %{shift_state: "P", speed: nil, power: nil, elevation: 5, time: now})

      assert_receive {:insert_position, ^drive, %{speed: 0, power: 0}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      assert_receive {:start_state, ^car, :online, date: _}

      assert_receive {:insert_position, ^car, %{latitude: 42.91, longitude: 42.81, speed: 0}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, elevation: 4}}}

      refute_receive _
    end

    test "discards fetch result", %{test: name} do
      me = self()
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, online_event()},
        {:ok, online_event(drive_state: %{timestamp: now_ts})},
        fn ->
          send(me, :continue?)

          receive do
            :continue ->
              {:ok,
               online_event(
                 drive_state: %{
                   timestamp: now_ts + 0,
                   latitude: 42.91,
                   longitude: 42.81,
                   shift_state: "P",
                   speed: 0,
                   power: 0
                 }
               )}
          after
            5_000 -> raise "No :continue after 5s"
          end
        end,
        fn ->
          send(me, :continue?)

          receive do
            :continue ->
              {:ok,
               online_event(
                 drive_state: %{
                   timestamp: now_ts + 4,
                   latitude: 42.91,
                   longitude: 42.81,
                   shift_state: "P",
                   speed: 0,
                   power: 0
                 }
               )}
          after
            5_000 -> raise "No :continue after 5s"
          end
        end,
        fn -> Process.sleep(10_000) end
      ]

      d1 = DateTime.from_unix!(now_ts + 1, :millisecond)
      d2 = DateTime.from_unix!(now_ts + 2, :millisecond)
      d3 = DateTime.from_unix!(now_ts + 2, :millisecond)
      d4 = DateTime.from_unix!(now_ts + 4, :millisecond)

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      stream(name, %{shift_state: "D", time: d1})
      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{date: ^d1}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving, elevation: 10}}}

      stream(name, %{shift_state: "D", time: d2})
      assert_receive {:insert_position, ^drive, %{date: ^d2}}

      assert capture_log(@log_opts, fn ->
               stream(name, %{shift_state: "P", speed: nil, power: nil, time: d3})
               assert_receive :continue?
               send(:"api_#{name}", :continue)

               assert_receive :continue?
               refute_receive _
             end) =~ """
             Discarded stale fetch result: %{
               last: %TeslaApi.Vehicle.State.Drive{
                 gps_as_of: nil,
                 heading: 120,
                 latitude: 42.1,
                 longitude: 42.0,
                 native_latitude: nil,
                 native_location_supported: nil,
                 native_longitude: nil,
                 native_type: nil,
                 power: 0,
                 shift_state: \"D\",
                 speed: 0,
                 timestamp: #{DateTime.to_unix(d1, :millisecond)}
               },
               now: %TeslaApi.Vehicle.State.Drive{
                 gps_as_of: nil,
                 heading: nil,
                 latitude: 42.91,
                 longitude: 42.81,
                 native_latitude: nil,
                 native_location_supported: nil,
                 native_longitude: nil,
                 native_type: nil,
                 power: 0,
                 shift_state: \"P\",
                 speed: 0,
                 timestamp: #{now_ts}
               }
             }
             """

      send(:"api_#{name}", :continue)

      assert_receive {:insert_position, ^drive, %{date: ^d4, speed: 0, power: 0}}
      assert_receive {:close_drive, ^drive, lookup_address: true}

      assert_receive {:start_state, ^car, :online, date: ^d4}
      assert_receive {:insert_position, ^car, %{date: ^d4}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    @tag :capture_log
    test "discards stale stream data", %{test: name} do
      now = DateTime.utc_now()

      events = [
        {:ok, online_event()},
        {:ok, online_event(drive_state: %{timestamp: DateTime.to_unix(now, :millisecond)})},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert capture_log(@log_opts, fn ->
               stream(name, %{shift_state: "P", time: DateTime.add(now, -1, :second)})
               refute_receive _
             end) =~ "Received stale stream data"
    end
  end

  describe "charging" do
    @tag :capture_log
    test "starts charging", %{test: name} do
      me = self()
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, online_event()},
        {:ok, online_event(drive_state: %{timestamp: now_ts})},
        fn ->
          send(me, :continue?)

          receive do
            :continue -> {:error, :closed}
          after
            5_000 -> raise "No :continue after 5s"
          end
        end,
        {:ok, charging_event(now_ts + 1, "Charging", 0.0)},
        {:ok, charging_event(now_ts + 2, "Charging", 1.0)},
        {:ok, charging_event(now_ts + 3, "Stopped", 1.1)},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert_receive :continue?
      stream(name, %{shift_state: nil, power: -1, time: now})
      send(:"api_#{name}", :continue)

      assert_receive {:start_charging_process, ^car, %{latitude: 0.0}, [lookup_address: true]}
      assert_receive {:insert_charge, cproc, %{date: _, charge_energy_added: 0.0}}
      assert_receive {:"$websockex_cast", :disconnect}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

      assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 1.0}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:insert_charge, ^cproc, %{date: _, charge_energy_added: 1.1}}
      assert_receive {:complete_charging_process, ^cproc}

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end

  describe "suspended" do
    test "fetches the vehicle state if the stream becomes inactive", %{test: name} do
      me = self()

      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:ok, online_event()},
        fn ->
          send(me, :continue?)

          receive do
            :continue -> {:ok, %TeslaApi.Vehicle{state: "asleep"}}
          after
            5_000 -> raise "No :continue after 5s"
          end
        end,
        fn -> Process.sleep(10_000) end
      ]

      :ok =
        start_vehicle(name, events, settings: %{use_streaming_api: true, suspend_min: 999_999_999})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert :ok = Vehicle.suspend_logging(name)
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

      send(name, {:stream, :inactive})

      assert_receive :continue?
      send(:"api_#{name}", :continue)

      assert_receive {:start_state, ^car, :asleep, []}
      assert_receive {:"$websockex_cast", :disconnect}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

      refute_receive _
    end

    @tag :capture_log
    test "discards stale stream data when suspended", %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, online_event(drive_state: %{timestamp: now_ts})},
        {:ok, online_event(drive_state: %{timestamp: now_ts + 1})},
        {:ok, online_event(drive_state: %{timestamp: now_ts + 2})},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert :ok = Vehicle.suspend_logging(name)
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

      assert capture_log(@log_opts, fn ->
               stream(name, %{shift_state: "D", time: DateTime.add(now, 1, :millisecond)})
               refute_receive _
             end) =~ "Received stale stream data"
    end
  end

  test "resumes logging when starting a drive", %{test: name} do
    now = DateTime.utc_now()

    events = [
      {:ok, online_event()},
      {:ok, online_event()},
      {:ok, online_event()},
      fn -> Process.sleep(10_000) end
    ]

    :ok =
      start_vehicle(name, events, settings: %{use_streaming_api: true, suspend_min: 999_999_999})

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

    stream(name, %{shift_state: "P", speed: 0, power: 0, elevation: 50, time: now})
    refute_receive _

    stream(name, %{shift_state: "D", speed: 50, power: 5, elevation: 50, time: now})
    assert_receive {:start_drive, ^car}
    assert_receive {:insert_position, _drive, position}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :driving, speed: 80, elevation: 50}}}

    assert position == %{
             latitude: 42.1,
             longitude: 42.0,
             speed: 80,
             battery_level: 60,
             date: now,
             elevation: 50,
             odometer: 1609.344,
             power: 5
           }

    refute_receive _
  end

  test "resumes logging when starting to charge", %{test: name} do
    me = self()
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event(drive_state: %{timestamp: now_ts})},
      {:ok, online_event(drive_state: %{timestamp: now_ts + 1})},
      {:ok, online_event(drive_state: %{timestamp: now_ts + 2})},
      fn ->
        send(me, :continue?)

        receive do
          :continue -> {:ok, charging_event(now_ts + 3, "Charging", 0.0)}
        after
          5_000 -> raise "No :continue after 5s"
        end
      end,
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert :ok = Vehicle.suspend_logging(name)
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

    stream(name, %{shift_state: nil, power: -5, time: DateTime.add(now, 2, :millisecond)})
    assert_receive :continue?
    send(:"api_#{name}", :continue)

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0}, [lookup_address: true]}, 1000
    assert_receive {:insert_charge, _cproc, %{date: _, charge_energy_added: 0.0}}
    assert_receive {:"$websockex_cast", :disconnect}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    refute_receive _
  end

  describe "updating" do
    test "disconnects stream", %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, online_event()},
        {:ok, online_event(drive_state: %{timestamp: now_ts})},
        {:ok, update_event(now_ts + 10, "installing", "2019.8.4 530d1d3")},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: true})

      assert_receive {:start_state, car_id, :online, date: _}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {ApiMock, {:stream, _eid, func}} when is_function(func)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert_receive {:start_update, ^car_id, date: _}
      assert_receive {:"$websockex_cast", :disconnect}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :updating}}}

      # Handles unexpected stream messages
      stream(name, %{time: DateTime.utc_now()})

      refute_receive _
    end
  end
end
