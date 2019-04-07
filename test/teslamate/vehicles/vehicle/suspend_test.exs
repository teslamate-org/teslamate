defmodule TeslaMate.Vehicles.Vehicle.SuspendTest do
  use TeslaMate.VehicleCase, async: true

  test "suspends after idling", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

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

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, 999, :online}
    refute_receive _, sudpend_after_idle_ms + suspend_ms - 20
    assert_receive {:start_state, 999, :asleep}, 200

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if preconditioning", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

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

    assert_receive {:start_state, 999, :online}

    # Stays online
    refute_receive _, round(suspend_ms * 1.5)
  end

  @tag :capture_log
  test "does not suspend if user is present", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    not_supendable =
      vehicle_full(
        drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{is_user_present: true}
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

    assert_receive {:start_state, 999, :online}

    # Stays online
    refute_receive _, round(suspend_ms * 1.5)
  end

  test "suspends if charging is complete", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.2)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, 999, :online}
    assert_receive {:start_charging_process, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.2}}
    refute_receive _, sudpend_after_idle_ms + suspend_ms - 20
    assert_receive {:start_state, 999, :asleep}

    refute_receive _
  end

  test "continues charging if suspending wasn't successful", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 5, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 6, "Charging", 0.3)},
      {:ok, charging_event(now_ts + 7, "Complete", 0.3)}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, 999, :online}
    assert_receive {:start_charging_process, 999, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.15}}

    refute_receive _, sudpend_after_idle_ms + suspend_ms - 20

    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.3}}
    assert_receive {:insert_charge, 99, %{date: _, charge_energy_added: 0.3}}

    refute_receive _, 200
  end

  defp charging_event(ts, charging_state, charge_energy_added) do
    vehicle_full(
      charge_state: %{
        timestamp: ts,
        charging_state: charging_state,
        charge_energy_added: charge_energy_added
      },
      drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0}
    )
  end
end
