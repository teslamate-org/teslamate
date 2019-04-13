defmodule TeslaMate.Vehicles.Vehicle.UpdatingTest do
  use TeslaMate.VehicleCase, async: true

  defp update_event(state, version) do
    alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

    online_event(
      vehicle_state: %{
        car_version: version,
        software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: state}
      }
    )
  end

  @tag :capture_log
  test "logs an update cycle", %{test: name} do
    events = [
      {:ok, online_event()},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, update_event("installing", "2019.8.4 530d1d3")},
      {:ok, update_event("", "2019.8.5 3aaa23d")}
    ]

    :ok = start_vehicle(name, events)

    assert_receive {:start_state, car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:online, %TeslaApi.Vehicle{}}}}

    assert_receive {:start_update, ^car_id}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:updating, %TeslaApi.Vehicle{}}}}
    assert_receive {:finish_update, _upate_id, "2019.8.5 3aaa23d"}, 200

    assert_receive {:start_state, ^car_id, :online}
    assert_receive {:insert_position, ^car_id, %{}}
    assert_receive {:pubsub, {:broadcast, _server, _topic, {:online, %TeslaApi.Vehicle{}}}}

    refute_receive _
  end
end
