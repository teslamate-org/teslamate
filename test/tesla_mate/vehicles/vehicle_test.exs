defmodule TeslaMate.Vehicles.VehicleTest do
  use TeslaMate.VehicleCase, async: true

  describe "start" do
    @tag :capture_log
    test "handles unkown and faulty states", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "unknown"}},
        {:error, %TeslaApi.Error{message: "boom"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0, vehicle_id: 1001}, events)

      refute_receive _
    end

    test "handles online state", %{test: name} do
      now = DateTime.utc_now()
      now_ts = DateTime.to_unix(now, :millisecond)

      events = [
        {:ok, %TeslaApi.Vehicle{state: "online"}},
        {:ok, vehicle_full(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :online}

      #       assert_receive {:insert_position,
      #                       %{
      #                         altitude: nil,
      #                         battery_level: nil,
      #                         date: ^now,
      #                         ideal_battery_range_km: nil,
      #                         latitude: 0.0,
      #                         longitude: 0.0,
      #                         odometer: nil,
      #                         outside_temp: nil,
      #                         power: nil,
      #                         speed: nil
      #                       }}

      refute_receive _
    end

    test "handles offline state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "offline"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :offline}

      refute_receive _
    end

    test "handles asleep state", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep"}}
      ]

      :ok = start_vehicle(name, %TeslaApi.Vehicle{id: 0}, events)

      assert_receive {:start_state, 999, :asleep}

      refute_receive _
    end
  end
end
