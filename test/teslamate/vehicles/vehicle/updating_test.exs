defmodule TeslaMate.Vehicles.Vehicle.UpdatingTest do
  use TeslaMate.VehicleCase, async: true

  @tag :capture_log
  test "logs an update cycle", %{test: name} do
    events = [
      {:ok, online_event()},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, %TeslaApi.Vehicle{state: "online", vehicle_state: nil}},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("", "2019.8.5 3aaa23d")}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online, since: s0}}}

    assert_receive {:start_update, ^car_id}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :updating, since: s1}}}
    assert DateTime.diff(s0, s1, :nanosecond) < 0
    assert_receive {:finish_update, _upate_id, "2019.8.5 3aaa23d"}, 200

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online, since: s2}}}
    assert DateTime.diff(s1, s2, :nanosecond) < 0

    refute_receive _
  end

  @tag :capture_log
  test "cancels an update", %{test: name} do
    events = [
      {:ok, online_event()},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("available", "2019.8.4 530d1d3")}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    assert_receive {:start_update, ^car_id}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :updating}}}
    assert_receive {:cancel_update, _upate_id}, 200

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, %Summary{state: :online}}}

    refute_receive _
  end
end
