defmodule TeslaMate.Vehicles.Vehicle.UpdatingTest do
  use TeslaMate.VehicleCase, async: true

  @tag :capture_log
  test "logs an update cycle", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, update_event(now_ts - 1, "available", nil, update_version: "2019.8.5 3aaa23d")},
      {:ok, update_event(now_ts, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(now_ts + 1, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(now_ts + 2, "installing", "2019.8.4 530d1d3")},
      {:ok, %TeslaApi.Vehicle{state: "online", vehicle_state: nil}},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, update_event(now_ts + 5, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(now_ts + 6, "", "2019.8.5 3aaa23d")},
      fn -> Process.sleep(10_000) end
    ]

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    end_date = DateTime.from_unix!(now_ts + 6, :millisecond)

    :ok = start_vehicle(name, events, settings: %{use_streaming_api: false})

    d0 = DateTime.from_unix!(now_ts - 1, :millisecond)
    assert_receive {:start_state, car_id, :online, date: ^d0}, 600
    assert_receive {:insert_position, ^car_id, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{
                       state: :online,
                       since: s0,
                       update_available: true,
                       update_version: "2019.8.5"
                     }}}

    assert_receive {:start_update, ^car_id, [date: ^start_date]}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{state: :updating, since: s1, version: "2019.8.4"}}}

    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:finish_update, _upate_id, "2019.8.5 3aaa23d", date: ^end_date}, 200

    d1 = DateTime.from_unix!(now_ts + 6, :millisecond)
    assert_receive {:start_state, ^car_id, :online, date: ^d1}
    assert_receive {:insert_position, ^car_id, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{state: :online, since: s2, version: "2019.8.5"}}}

    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  @tag :capture_log
  test "logs an update if the status is not empty", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, update_event(now_ts - 1, "available", nil, update_version: "2019.8.5 3aaa23d")},
      {:ok, update_event(now_ts, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(now_ts + 1, "foo", "2019.8.5 3aaa23d")},
      fn -> Process.sleep(10_000) end
    ]

    start_date = DateTime.from_unix!(now_ts, :millisecond)
    end_date = DateTime.from_unix!(now_ts + 1, :millisecond)

    :ok = start_vehicle(name, events, settings: %{use_streaming_api: false})

    d0 = DateTime.from_unix!(now_ts - 1, :millisecond)
    assert_receive {:start_state, car_id, :online, date: ^d0}, 600
    assert_receive {:insert_position, ^car_id, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{
                       state: :online,
                       since: s0,
                       update_available: true,
                       update_version: "2019.8.5"
                     }}}

    assert_receive {:start_update, ^car_id, date: ^start_date}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :updating, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:finish_update, _upate_id, "2019.8.5 3aaa23d", date: ^end_date}, 200

    d1 = DateTime.from_unix!(now_ts + 1, :millisecond)
    assert_receive {:start_state, ^car_id, :online, date: ^d1}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  @tag :capture_log
  test "cancels an update", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok,
       update_event(now_ts, "installing", "2019.8.4 530d1d3", update_version: "2019.8.5 3aaa23d")},
      {:ok,
       update_event(now_ts + 10, "available", "2019.8.4 530d1d3",
         update_version: "2019.8.5 3aaa23d"
       )},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events, settings: %{use_streaming_api: false})

    d0 = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_state, car_id, :online, date: ^d0}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    date = DateTime.from_unix!(now_ts, :millisecond)
    assert_receive {:start_update, ^car_id, date: ^date}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{state: :updating, version: "2019.8.4", update_version: "2019.8.5"}}}

    assert_receive {:cancel_update, _upate_id}, 200

    d1 = DateTime.from_unix!(now_ts + 10, :millisecond)
    assert_receive {:start_state, ^car_id, :online, date: ^d1}, 600
    assert_receive {:insert_position, ^car_id, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _server, _topic,
                     %Summary{state: :online, version: "2019.8.4", update_version: "2019.8.5"}}}

    refute_receive _
  end
end
