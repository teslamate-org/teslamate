defmodule TeslaMate.Vehicles.Vehicle.UpdatingTest do
  use TeslaMate.VehicleCase, async: true

  defp update_event(ts, state, version) do
    alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

    vehicle_full(
      drive_state: %{timestamp: ts, latitude: 0.0, longitude: 0.0},
      vehicle_state: %{
        car_version: version,
        software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: state}
      }
    )
  end

  @tag :capture_log
  test "logs an update cycle", %{test: name} do
    events = [
      {:ok, %TeslaApi.Vehicle{state: "online"}},
      {:ok, update_event(0, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(1, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(2, "installing", "2019.8.4 530d1d3")},
      {:error, :vehicle_unavailable},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, update_event(3, "installing", "2019.8.4 530d1d3")},
      {:ok, update_event(4, "", "2019.8.5 3aaa23d")}
    ]

    :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

    assert_receive {:start_state, car_id, :online}

    assert_receive {:start_update, ^car_id}
    assert_receive {:finish_update, _upate_id, "2019.8.5 3aaa23d"}, 200

    assert_receive {:start_state, ^car_id, :online}

    refute_receive _
  end
end
