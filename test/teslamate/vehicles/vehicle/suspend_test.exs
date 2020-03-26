defmodule TeslaMate.Vehicles.Vehicle.SuspendTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle

  import ExUnit.CaptureLog

  @log_opts format: "[$level] $message\n",
            colors: [enabled: false]

  test "suspends when idling", %{test: name} do
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
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:start_state, ^car, :asleep, []}, round(suspend_ms * 1.2)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  test "does not suspend if sleep mode is disabled", %{test: name} do
    suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: false}
      )

    events = [
      {:ok, suspendable}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        settings: %{
          sleep_mode_enabled: false,
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    refute_receive _
  end

  test "suspends if sleep mode is disabled but enabled for location", %{test: name} do
    suspendable =
      online_event(drive_state: %{timestamp: 0, latitude: -50.606993, longitude: 165.972471})

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
        settings: %{
          sleep_mode_enabled: false,
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        },
        whitelist: [{-50.606993, 165.972471}]
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:start_state, ^car, :asleep, []}, round(suspend_ms * 1.1)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  test "does not suspend if sleep mode is disabled for the current location", %{test: name} do
    suspendable =
      online_event(drive_state: %{timestamp: 0, latitude: -50.606993, longitude: 165.972471})

    events = [
      {:ok, suspendable}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        settings: %{
          sleep_mode_enabled: true,
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        },
        blacklist: [{-50.606993, 165.972471}]
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

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
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if user is present", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{is_user_present: true, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  test "does not suspend if sentry mode is active", %{test: name} do
    not_supendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: true, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_supendable}
    ]

    sudpend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}

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
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    d0 = DateTime.from_unix!(0, :millisecond)
    assert_receive {:start_state, car, :online, date: ^d0}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:insert_charge, charge_id, %{date: _, charge_energy_added: 0.1}}

    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:insert_charge, ^charge_id, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:complete_charging_process, ^charge_id}

    assert_receive {:start_state, ^car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    # ...

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:start_state, ^car, :asleep, []}, round(suspend_ms * 1.2)
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

    refute_receive _
  end

  test "continues charging if suspending wasn't successful", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 5, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 5, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 6, "Charging", 0.3)}
    ]

    sudpend_after_idle_ms = 1
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    d0 = DateTime.from_unix!(0, :millisecond)
    assert_receive {:start_state, car, :online, date: ^d0}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:insert_charge, cproc_0, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^cproc_0, %{date: _, charge_energy_added: 0.15}}
    assert_receive {:complete_charging_process, ^cproc_0}

    assert_receive {:start_state, ^car, :online, date: ^d0}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

    # new charging session

    TestHelper.eventually(
      fn -> assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}} end,
      delay: suspend_ms,
      attempts: 3
    )

    assert_receive {:insert_charge, cproc_1, %{date: _, charge_energy_added: 0.2}}
    assert cproc_0 != cproc_1

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:insert_charge, ^cproc_1, %{date: _, charge_energy_added: 0.3}}

    # ...
  end

  test "broadcasts if vehicle gets (un)locked when idling", %{test: name} do
    unlocked =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{locked: false, car_version: ""}
      )

    locked =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{locked: true, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, unlocked},
      {:ok, locked},
      {:ok, unlocked},
      {:ok, locked}
    ]

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: 100_000,
          suspend_min: 1000
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: false}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: true}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: false}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: true}}}

    refute_receive _
  end

  test "broadcasts if sentry mode gets turned on/off", %{test: name} do
    sentry_mode_on =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: true, car_version: ""}
      )

    sentry_mode_off =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: false, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, sentry_mode_on},
      {:ok, sentry_mode_off},
      {:ok, sentry_mode_on},
      {:ok, sentry_mode_off}
    ]

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: 100_000,
          suspend_min: 1000
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: false}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: false}}}

    refute_receive _
  end

  test "does not suspend drive_state is not available", %{test: name} do
    events = [
      {:ok, online_event()},
      {:ok, online_event()},
      {:ok,
       %TeslaApi.Vehicle{
         state: "online",
         drive_state: nil,
         vehicle_state: %{sentry_mode: false, car_version: ""},
         vehicle_config: %TeslaApi.Vehicle.State.VehicleConfig{
           car_type: "model3",
           trim_badging: nil,
           exterior_color: "White",
           wheel_type: "foo",
           spoiler_type: "None"
         }
       }}
    ]

    assert capture_log(@log_opts, fn ->
             :ok =
               start_vehicle(name, events,
                 settings: %{suspend_after_idle_min: 10, suspend_min: 10_000_000}
               )

             assert_receive {:start_state, car, :online, date: _}
             assert_receive {:insert_position, ^car, %{}}
             assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

             refute_receive _
           end) =~ "[warn] Cannot determine vehicle position\n"
  end

  describe "req_not_unlocked" do
    @tag :capture_log
    test "does not suspend if vehicle is unlocked", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{locked: false, car_version: ""}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_supendable}
      ]

      sudpend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          settings: %{
            req_not_unlocked: true,
            suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
            suspend_min: suspend_ms
          }
        )

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: false}}}

      refute_receive _, round(suspend_ms * 0.5)

      refute_receive _
    end

    @tag :capture_log
    test "w/o does suspend if vehicle is unlocked", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{locked: false, car_version: ""}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_supendable}
      ]

      sudpend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          settings: %{
            req_not_unlocked: false,
            suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
            suspend_min: suspend_ms
          }
        )

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: false}}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, locked: false}}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, locked: false}}}
      assert_receive {:insert_position, ^car, %{}}

      refute_receive _, 50
    end
  end

  describe "req_no_shift_state_reading" do
    @tag :capture_log
    test "does not suspend if shift_state is not nil", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, shift_state: "P", latitude: 0.0, longitude: 0.0}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_supendable}
      ]

      sudpend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          req_no_shift_state_reading: true,
          suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
          suspend_min: suspend_ms
        )

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}
      refute_receive _, round(suspend_ms * 0.5)

      refute_receive _
    end
  end

  describe "req_no_temp_reading" do
    @tag :capture_log
    test "does not suspend if outside_temp is not nil", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          climate_state: %{outside_temp: 20.0}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_supendable}
      ]

      sudpend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          settings: %{
            req_no_temp_reading: true,
            suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
            suspend_min: suspend_ms
          }
        )

      date = DateTime.from_unix!(0, :millisecond)
      assert_receive {:start_state, car, :online, date: ^date}
      assert_receive {:insert_position, ^car, %{}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, outside_temp: 20.0}}}

      refute_receive _, round(suspend_ms * 0.5)

      refute_receive _
    end

    @tag :capture_log
    test "does not suspend if inside_temp is not nil", %{test: name} do
      not_supendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          climate_state: %{inside_temp: 20.0}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_supendable}
      ]

      sudpend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          settings: %{
            req_no_temp_reading: true,
            suspend_after_idle_min: round(sudpend_after_idle_ms / 60),
            suspend_min: suspend_ms
          }
        )

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {:insert_position, ^car, %{}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, inside_temp: 20.0}}}

      refute_receive _, round(suspend_ms * 0.5)

      refute_receive _
    end
  end
end
