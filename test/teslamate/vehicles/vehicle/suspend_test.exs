defmodule TeslaMate.Vehicles.Vehicle.SuspendTest do
  use TeslaMate.VehicleCase, async: true

  alias TeslaMate.Vehicles.Vehicle.Summary

  test "suspends when idling", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    suspendable = fn ts ->
      online_event(
        drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: false}
      )
    end

    events = [
      {:ok, suspendable.(now_ts + 0)},
      {:ok, suspendable.(now_ts + 1)},
      {:ok, suspendable.(now_ts + 2)},
      {:ok, suspendable.(now_ts + 3)},
      {:ok, suspendable.(now_ts + 4)},
      {:ok, suspendable.(now_ts + 5)},
      {:ok, suspendable.(now_ts + 6)},
      {:ok, suspendable.(now_ts + 7)},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:start_state, ^car, :asleep, []}
    assert_receive {:"$websockex_cast", :disconnect}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  test "counts how long it takes to fall asleep", %{test: name} do
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    suspendable = fn ts, t ->
      online_event(
        drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: false, outside_temp: t}
      )
    end

    events = [
      {:ok, suspendable.(now_ts + 0, 10.0)},
      {:ok, suspendable.(now_ts + 1, 10.1)},
      {:ok, suspendable.(now_ts + 2, 10.2)},
      {:ok, suspendable.(now_ts + 3, 10.3)},
      {:ok, suspendable.(now_ts + 4, 10.4)},
      {:ok, suspendable.(now_ts + 5, 10.5)},
      {:ok, suspendable.(now_ts + 6, 10.6)},
      {:ok, suspendable.(now_ts + 7, 10.7)},
      {:ok, suspendable.(now_ts + 8, 10.8)},
      {:ok, suspendable.(now_ts + 9, 10.9)},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: s0, outside_temp: 10.1}}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: ^s0, outside_temp: 10.2}}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: ^s0, outside_temp: 10.3}}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: ^s0, outside_temp: 10.4}}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: ^s0, outside_temp: 10.5}}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :online, since: ^s0, outside_temp: 10.6}}}

    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _, _, %Summary{state: :suspended, since: s1, outside_temp: 10.7}}}

    assert DateTime.diff(s0, s1, :nanosecond) < 0

    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub,
                    {:broadcast, _, _,
                     %Summary{state: :suspended, since: ^s1, outside_temp: 10.9}}}

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if preconditioning", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        climate_state: %{is_preconditioning: true}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if user is present", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{is_user_present: true, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if a download is in progress", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{
          software_update: %TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate{
            status: "downloading",
            download_perc: 10
          },
          car_version: ""
        }
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 200

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  test "does not suspend if sentry mode is active", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{sentry_mode: true, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}

    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if any of the doors are open", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{df: 0, dr: 0, pf: 1, pr: 0, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, doors_open: true}}}

    refute_receive _, round(suspend_ms * 0.5)

    refute_receive _
  end

  @tag :capture_log
  test "does not suspend if the rear or front trunk is open", %{test: name} do
    not_suspendable =
      online_event(
        drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
        vehicle_state: %{rt: 0, ft: 1, car_version: ""}
      )

    events = [
      {:ok, online_event()},
      {:ok, not_suspendable}
    ]

    suspend_after_idle_ms = 10
    suspend_ms = 100

    :ok =
      start_vehicle(name, events,
        settings: %{
          suspend_after_idle_min: round(suspend_after_idle_ms / 60),
          suspend_min: suspend_ms
        }
      )

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, frunk_open: true}}}

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
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.3)},
      {:ok, %TeslaApi.Vehicle{state: "asleep"}},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    d0 = DateTime.from_unix!(now_ts + 1, :millisecond)
    assert_receive {:start_state, car, :online, date: ^d0}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:"$websockex_cast", :disconnect}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:insert_charge, charge_id, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:insert_charge, ^charge_id, %{date: _, charge_energy_added: 0.2}}
    assert_receive {:complete_charging_process, ^charge_id}

    assert_receive {:start_state, ^car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    # ...

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:start_state, ^car, :asleep, []}, 50
    assert_receive {:"$websockex_cast", :disconnect}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep}}}

    refute_receive _
  end

  test "continues charging if suspending wasn't successful", %{test: name} do
    now = DateTime.utc_now()
    now_ts = DateTime.to_unix(now, :millisecond)

    events = [
      {:ok, online_event()},
      {:ok, charging_event(now_ts + 0, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 1, "Charging", 0.1)},
      {:ok, charging_event(now_ts + 2, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 3, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 4, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 5, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 6, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 7, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 8, "Complete", 0.15)},
      {:ok, charging_event(now_ts + 9, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 10, "Charging", 0.2)},
      {:ok, charging_event(now_ts + 11, "Charging", 0.3)}
    ]

    :ok = start_vehicle(name, events)

    d0 = DateTime.from_unix!(now_ts + 0, :millisecond)
    assert_receive {:start_state, car, :online, date: ^d0}
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:start_charging_process, ^car, %{latitude: 0.0, longitude: 0.0},
                    [lookup_address: true]}

    assert_receive {:insert_charge, cproc_0, %{date: _, charge_energy_added: 0.1}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}

    assert_receive {:insert_charge, ^cproc_0, %{date: _, charge_energy_added: 0.15}}
    assert_receive {:complete_charging_process, ^cproc_0}

    d1 = DateTime.from_unix!(now_ts + 2, :millisecond)
    assert_receive {:start_state, ^car, :online, date: ^d1}
    assert_receive {:insert_position, ^car, %{}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended}}}

    # new charging session

    TestHelper.eventually(
      fn -> assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}} end,
      delay: 50,
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
      {:ok, locked},
      fn -> Process.sleep(10_000) end
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car, :online, date: _}
    assert_receive {ApiMock, {:stream, 1000, _}}
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
    assert_receive {ApiMock, {:stream, 1000, _}}
    assert_receive {:insert_position, ^car, %{}}

    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: false}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: true}}}
    assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, sentry_mode: false}}}

    refute_receive _
  end

  describe "req_not_unlocked" do
    @tag :capture_log
    test "does not suspend if vehicle is unlocked", %{test: name} do
      not_suspendable =
        online_event(
          drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{locked: false, car_version: ""}
        )

      events = [
        {:ok, online_event()},
        {:ok, not_suspendable}
      ]

      suspend_after_idle_ms = 10
      suspend_ms = 100

      :ok =
        start_vehicle(name, events,
          settings: %{
            req_not_unlocked: true,
            suspend_after_idle_min: round(suspend_after_idle_ms / 60),
            suspend_min: suspend_ms
          }
        )

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, locked: false}}}

      refute_receive _, round(suspend_ms * 0.5)

      refute_receive _
    end

    @tag :capture_log
    test "w/o does suspend if vehicle is unlocked", %{test: name} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      not_suspendable = fn ts ->
        online_event(
          drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0},
          vehicle_state: %{locked: false, car_version: ""}
        )
      end

      events = [
        {:ok, not_suspendable.(now_ts + 0)},
        {:ok, not_suspendable.(now_ts + 1)},
        {:ok, not_suspendable.(now_ts + 2)},
        {:ok, not_suspendable.(now_ts + 3)},
        {:ok, not_suspendable.(now_ts + 4)},
        {:ok, not_suspendable.(now_ts + 5)},
        {:ok, not_suspendable.(now_ts + 6)},
        {:ok, not_suspendable.(now_ts + 7)},
        {:ok, not_suspendable.(now_ts + 8)},
        {:ok, not_suspendable.(now_ts + 9)},
        {:ok, not_suspendable.(now_ts + 10)},
        {:ok, not_suspendable.(now_ts + 11)},
        {:ok, not_suspendable.(now_ts + 12)},
        fn -> Process.sleep(10_000) end
      ]

      :ok = start_vehicle(name, events, settings: %{req_not_unlocked: false})

      assert_receive {:start_state, car, :online, date: _}
      assert_receive {ApiMock, {:stream, 1000, _}}
      assert_receive {:insert_position, ^car, %{}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online, since: s0}}}

      d0 = DateTime.from_unix!(now_ts + 7, :millisecond)
      assert_receive {:insert_position, ^car, %{date: ^d0}}
      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :suspended, since: s1}}}
      assert DateTime.diff(s0, s1, :nanosecond) < 0

      d1 = DateTime.from_unix!(now_ts + 9, :millisecond)
      assert_receive {:insert_position, ^car, %{date: ^d1}}

      d2 = DateTime.from_unix!(now_ts + 11, :millisecond)
      assert_receive {:insert_position, ^car, %{date: ^d2}}

      refute_receive _, 500
    end
  end
end
