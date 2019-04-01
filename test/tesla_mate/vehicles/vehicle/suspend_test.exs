defmodule TeslaMate.Vehicles.Vehicle.SuspendTest do
  use TeslaMate.VehicleCase, async: true

  test "suspends after idling", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :microsecond)

    suspendable =
      vehicle_full(
        drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: false}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, suspendable},
      {:ok, suspendable},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}}
    ]

    sudpend_after_idle_ms = 0
    suspend_ms = 500

    :ok =
      start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:insert_position, %{date: ^now, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_state, :online}

    assert_receive {:insert_position, %{date: _, latitude: 0.0, longitude: 0.0}}
    refute_receive _, sudpend_after_idle_ms + suspend_ms - 20

    assert_receive {:start_state, :asleep}

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if preconditioning", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :microsecond)

    not_supendable =
      vehicle_full(
        drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: true}
      )

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:insert_position, %{date: ^now, latitude: 0.0, longitude: 0.0}}
    assert_receive {:start_state, :online}

    # Stays online
    refute_receive _, round(suspend_ms * 1.5)
  end
end
