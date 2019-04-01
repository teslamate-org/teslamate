defmodule TeslaMate.Vehicles.Vehicle.DrivingTest do
  use TeslaMate.VehicleCase, async: true

  defp drive_event(ts, shift_state, speed) do
    vehicle_full(
      drive_state: %{
        timestamp: ts,
        latitude: 0.1,
        longitude: 0.1,
        shift_state: shift_state,
        speed: speed
      }
    )
  end

  test "logs a full drive", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :microsecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, drive_event(now_ts + 1, "D", 50)},
      {:ok, drive_event(now_ts + 2, "N", 0)},
      {:ok, drive_event(now_ts + 3, "R", -5)},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:insert_position, %{date: ^now, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_state, :online}

    assert_receive :start_drive_state
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 50}}
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 0}}
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: -5}}
    assert_receive :close_drive_state

    assert_receive {:insert_position, %{date: _, latitude: 0.2, longitude: 0.2, speed: nil}}
    assert_receive {:start_state, :online}

    refute_receive _
  end

  @tag :capture_log
  test "handles a connection loss when driving", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :microsecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, drive_event(now_ts + 1, "D", 50)},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:error, :unavailable},
      {:ok, %TeslaApi.Vehicle{state: "unknown"}},
      {:ok, drive_event(now_ts + 2, "D", 55)},
      {:ok, drive_event(now_ts + 3, "D", 40)},
      {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.2, longitude: 0.2})}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:insert_position, %{date: ^now, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_state, :online}

    assert_receive :start_drive_state
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 50}}
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 55}}
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 40}}
    assert_receive :close_drive_state

    assert_receive {:insert_position, %{date: _, latitude: 0.2, longitude: 0.2, speed: nil}}
    assert_receive {:start_state, :online}

    refute_receive _
  end

  test "Transitions directly into driving state", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :microsecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, drive_event(now_ts, "N", 0)}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:insert_position, %{date: ^now, latitude: 0.1, longitude: 0.1}}
    assert_receive {:start_state, :online}

    assert_receive :start_drive_state
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 0}}
    assert_receive {:insert_position, %{date: _, latitude: 0.1, longitude: 0.1, speed: 0}}
    # ...

    refute_received _
  end
end
