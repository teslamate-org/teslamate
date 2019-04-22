defmodule TeslaMate.Vehicles.Vehicle.SuspendTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle

  test "suspends after idling", %{test: name} do
    suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: false}
      )

    events = [
      {:ok, online_event()},
      {:ok, online_event()},
      {:ok, suspendable},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

    assert_receive {:start_state, ^car_id, :asleep}, round(suspend_ms * 1.1)
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if preconditioning", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: true}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if user is present", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{is_user_present: true}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if sentry mode is active", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: true}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if shift_state is not nil", %{test: name} do
    not_supendable =
      online_event(drive_state: %{timestamp: 0, shift_state: "P", latitude: 0.0, longitude: 0.0})

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  test "suspends if charging is complete", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.2)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging}}}
    assert_receive {:insert_charge, charge_id, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging_complete}}}
    assert_receive {:insert_charge, ^charge_id, %{date: _, charge_energy_added: 0.2}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

    assert_receive {:start_state, ^car_id, :asleep}, round(suspend_ms * 1.1)
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

    refute_receive _
  end

  test "continues charging if suspending wasn't successful", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 5, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 6, "Charging", 0.3)}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        sudpend_after_idle_min: round(sudpend_after_idle_ms / 60),
        suspend_min: suspend_ms
      )

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0}}
    assert_receive {:insert_charge, charging_event, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^charging_event, %{date: _, charge_energy_added: 0.15}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging_complete}}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging}}},
                   round(suspend_ms * 1.1)

    assert_receive {:insert_charge, ^charging_event, %{date: _, charge_energy_added: 0.2}}

    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging}}}
    assert_receive {:insert_charge, ^charging_event, %{date: _, charge_energy_added: 0.3}}

    # ...
  end

  describe "suspend_logging/1" do
    alias TeslaMate.Vehicles.Vehicle

    test "immediately returns :ok if asleep", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :asleep}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :asleep}}}

      assert :ok = Vehicle.suspend_logging(name)
      refute_receive _
    end

    test "immediately returns :ok if offline", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :offline}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :offline}}}

      assert :ok = Vehicle.suspend_logging(name)
      refute_receive _
    end

    test "immediately returns :ok if already suspending", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok = start_vehicle(name, events, suspend_min: 1000)
      assert_receive {:start_state, car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      assert :ok = Vehicle.suspend_logging(name)
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}
      assert :ok = Vehicle.suspend_logging(name)

      refute_receive _
    end

    test "cannot be suspended if vehicle is preconditioning", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          climate_state: %{is_preconditioning: true}
        )

      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, not_supendable}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :preconditioning} = Vehicle.suspend_logging(name)
    end

    test "cannot be suspended if user is present", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{is_user_present: true}
        )

      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, not_supendable}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :user_present} = Vehicle.suspend_logging(name)
    end

    test "cannot be suspended if sentry mode is active", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{sentry_mode: true}
        )

      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, not_supendable}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :sentry_mode} = Vehicle.suspend_logging(name)
    end

    test "cannot be suspended if shift_state is not nil", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, shift_state: "P", latitude: 0.0, longitude: 0.0}
        )

      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, not_supendable}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :shift_state} = Vehicle.suspend_logging(name)
    end

    test "cannot be suspended while driving", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, drive_event(0, "D", 0)}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :vehicle_not_parked} = Vehicle.suspend_logging(name)
    end

    test "cannot be suspended while charing is not complete", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, charging_event(0, "Charging", 1.5)}
      ]

      :ok = start_vehicle(name, events)
      assert_receive {:start_state, _, :online}

      assert {:error, :charging_in_progress} = Vehicle.suspend_logging(name)
    end

    test "suspends when charging is complete", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, charging_event(0, "Complete", 1.5)}
      ]

      :ok = start_vehicle(name, events, suspend_min: 1_000_000)

      assert_receive {:start_state, car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      assert_receive {:start_charging_process, ^car_id, %{date: _, latitude: 0.0, longitude: 0.0}}
      assert_receive {:insert_charge, _charging_id, %{date: _, charge_energy_added: 1.5}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :charging_complete}}}

      assert :ok = Vehicle.suspend_logging(name)
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      refute_receive _
    end

    test "suspends when idling", %{test: name} do
      events = [
        {:ok, online_event()}
      ]

      :ok =
        start_vehicle(name, events,
          sudpend_after_idle_min: 100,
          suspend_min: 1000
        )

      assert_receive {:start_state, car_id, :online}
      assert_receive {:insert_position, ^car_id, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

      assert :ok = Vehicle.suspend_logging(name)
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :suspended}}}

      refute_receive _
    end
  end
end
