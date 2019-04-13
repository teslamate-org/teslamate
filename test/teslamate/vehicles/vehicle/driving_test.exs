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

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:start_trip, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 97, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 48, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: -8, trip_id: 111}}
    assert_receive {:close_trip, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}

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

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:start_trip, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 80, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 89, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 64, trip_id: 111}}
    assert_receive {:close_trip, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}

    refute_receive _
  end

  test "transitions directly into driving state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "N", 0)}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:start_trip, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 0, trip_id: 111}}
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

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}

    refute_receive _
  end

  test "shift_state P does not trigger position inserts", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, drive_event(now_ts, "D", 5)},
      {:ok, drive_event(now_ts, "D", 15)},
      {:ok, drive_event(now_ts, "P", 0)},
      {:ok, drive_event(now_ts, "P", 0)},
      {:ok, drive_event(now_ts, "P", 0)},
      {:ok, drive_event(now_ts, nil, 0)}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:start_trip, ^car_id}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 8, trip_id: 111}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:insert_position, ^car_id, %{longitude: 0.1, speed: 24, trip_id: 111}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:driving, %TeslaApi.Vehicle{}}}}

    assert_receive {:close_trip, 111}

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, {:online, %TeslaApi.Vehicle{}}}}

    refute_receive _
  end
end
