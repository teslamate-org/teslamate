defmodule TeslaMate.Vehicles.VehicleTest do
  use TeslaMate.VehicleCase, async: true

  describe "starting" do
    @tag :capture_log
    test "handles unknown and faulty states", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "unknown"}},
        {:error, %TeslaApi.Error{reason: :boom, message: "boom"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :unavailable, healthy: true}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{healthy: false, state: :unavailable}}}

      refute_receive _
    end

    test "handles online state", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "handles offline state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, _car, :offline, []}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      refute_receive _
    end

    test "handles asleep state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, _car, :asleep, []}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      refute_receive _
    end
  end

  describe "resume_logging/1" do
    alias TeslaMate.Vehicles.Vehicle

    test "does nothing of already online", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online, date: _}, 100
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      assert :ok = Vehicle.resume_logging(name)

      refute_receive _
    end

    test "increases polling frequency if asleep", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :asleep, []}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      assert :ok = Vehicle.resume_logging(name)

      assert_receive {:start_state, ^car, :online, date: _}, 100
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "increases polling frequency if offline", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, %TeslaApi.Vehicle{state: "offline"}},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :offline, []}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      assert :ok = Vehicle.resume_logging(name)

      assert_receive {:start_state, ^car, :online, date: _}, 100
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end

  describe "settings change" do
    alias TeslaMate.Vehicles.Vehicle
    alias TeslaMate.Settings.CarSettings

    test "applies new sleep settings", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok =
        start_vehicle(name, events,
          settings: %{
            suspend_after_idle_min: 999_999_999,
            suspend_min: 10_000,
            use_streaming_api: false
          }
        )

      # Online
      assert_receive {:start_state, %Car{id: car_id} = car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      refute_receive _, 500

      # Reduce suspend_after_idle_min
      send(name, %CarSettings{
        suspend_after_idle_min: 1,
        suspend_min: 10_000,
        use_streaming_api: false
      })

      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      assert_receive {:insert_position,
                      %Car{
                        id: ^car_id,
                        settings: %CarSettings{suspend_after_idle_min: 1, suspend_min: 10_000}
                      }, %{}}

      refute_receive _
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "restarts if the eid changed", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :vehicle_not_found}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      # Too many errors
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: false}}}

      # Killed
      assert_receive {VehiclesMock, :kill}
    end

    @tag :capture_log
    test "reports the health status", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :unknown}
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      # ...

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: false}}}, 1000
    end

    @tag :capture_log
    test "handles timeout errors", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :timeout},
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :timeout},
        {:error, :timeout},
        {:error, :closed},
        {:error, :closed},
        {:error, :timeout},
        {:ok, online_event()},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      refute_receive _, 100
    end

    @tag :capture_log
    test "notices if vehicle is in service ", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :vehicle_in_service},
        {:error, :vehicle_in_service},
        {:ok, online_event()},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{use_streaming_api: false})

      # Online
      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      refute_receive _, 400
    end

    test "ends a drive if vehicle is in service", %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      events = [
        {:ok, online_event()},
        {:ok, drive_event(now_ts + 0, "D", 5)},
        {:ok, drive_event(now_ts + 1, "D", 50)},
        {:error, :vehicle_in_service},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}

      assert_receive {:start_drive, ^car}
      assert_receive {:insert_position, drive, %{longitude: 0.1, speed: 8}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :driving}}}
      assert_receive {:insert_position, ^drive, %{longitude: 0.1, speed: 80}}
      assert_receive {:close_drive, ^drive, []}
      assert_receive {:"$websockex_cast", :disconnect}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :start}}}

      refute_receive _
    end

    @tag :capture_log
    test "stops polling if signed out", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        {:error, :not_signed_in},
        # next events shall just show that polling stops
        {:ok, online_event()},
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events)

      # Online
      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, healthy: true}}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :start, healthy: false}}}

      refute_receive _
    end

    @tag :capture_log
    test "broadcasts the summary when the health check succeeds again", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)

      fuse_name =
        TestHelper.eventually(
          fn ->
            assert %Vehicle.Summary{state: :asleep, healthy: true, car: %Car{id: id}} =
                     Vehicle.summary(name)

            :"#{Vehicle}_#{id}_api_error"
          end,
          delay: 10
        )

      assert_receive {:start_state, _car, :asleep, []}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, healthy: true}}}

      :ok = :fuse.circuit_disable(fuse_name)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, healthy: false}}}

      :ok = :fuse.circuit_enable(fuse_name)
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, healthy: true}}}

      refute_receive _
    end
  end

  describe "summary" do
    test "returns the summary if no api request was completed yet", %{test: name} do
      events = [
        fn ->
          Process.sleep(10_000)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicle(name, events)

      for _ <- 1..10 do
        assert %Vehicle.Summary{state: :unavailable, healthy: true} = Vehicle.summary(name)
      end
    end

    test "returns the summary even if the api call is blocked", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event()},
        fn ->
          Process.sleep(10_000)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicle(name, events)

      assert_receive {:start_state, _car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}

      for _ <- 1..10 do
        assert %Vehicle.Summary{state: :online, healthy: true} = Vehicle.summary(name)
      end
    end
  end

  describe "updates" do
    test "logs the current software version at first startup", %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      events = [
        {:ok,
         online_event(vehicle_state: %{timestamp: now_ts, car_version: "42.42.42.0 b2ab650"})}
      ]

      :ok = start_vehicle(name, events, last_update: nil)
      date = DateTime.from_unix!(now_ts, :millisecond)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:insert_missed_update, ^car, "42.42.42.0 b2ab650", date: ^date}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "logs missing updates", %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      events = [
        {:ok,
         online_event(vehicle_state: %{timestamp: now_ts, car_version: "2020.12.10 e0ccfda3d911"})}
      ]

      :ok = start_vehicle(name, events, last_update: %Update{version: "2020.12.5 e2179e0650f0"})
      date = DateTime.from_unix!(now_ts, :millisecond)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:insert_missed_update, ^car, "2020.12.10 e0ccfda3d911", date: ^date}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end

    test "does not log updates <= current version", %{test: name} do
      events = [
        {:ok, online_event()},
        {:ok, online_event(vehicle_state: %{car_version: "2019.40.10.7 ad132c7b057e"})},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()},
        {:ok, online_event(vehicle_state: %{car_version: "2019.40.10.6"})},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()},
        {:ok, online_event(vehicle_state: %{car_version: "2019.40.2.6"})},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, online_event()},
        {:ok, online_event(vehicle_state: %{car_version: "2019.40.9"})},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}},
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok =
        start_vehicle(name, events, last_update: %Update{version: "2019.40.10.7 ad132c7b057e"})

      for _ <- 1..4 do
        assert_receive {:start_state, car, :online, date: _}
        assert_receive {ApiMock, {:stream, 1000, _}}
        assert_receive {:insert_position, ^car, %{}}
        assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
        assert_receive {:start_state, ^car, :asleep, []}
        assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}
        assert_receive {:"$websockex_cast", :disconnect}
      end

      refute_receive _
    end

    @tag :capture_log
    test "handles unexpected :car_version's", %{test: name} do
      events = [
        {:ok, online_event(vehicle_state: %{car_version: nil})}
      ]

      :ok = start_vehicle(name, events, last_update: nil)

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

      refute_receive _
    end
  end
end
