defmodule TeslaMate.VehiclesTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.Vehicles

  @tag :capture_log
  test "kill/0" do
    {:ok, _} = start_supervised({Vehicles, vehicles: []})
    ref = Process.monitor(Vehicles)

    assert true = Vehicles.kill()
    assert_receive {:DOWN, ^ref, :process, {Vehicles, :nonode@nohost}, :killed}

    refute_receive _
  end

  test "restart/0" do
    {:ok, _pid} =
      start_supervised(
        {ApiMock, name: :api_vehicle, events: [{:ok, online_event()}], pid: self()}
      )

    {:ok, _pid} =
      start_supervised(
        {Vehicles,
         vehicle: VehicleMock,
         vehicles: [
           %TeslaApi.Vehicle{
             display_name: "foo",
             id: 424_242,
             vehicle_id: 4040,
             vin: "zzzzzzz"
           }
         ]}
      )

    ref = Process.monitor(Vehicles)

    assert :ok = Vehicles.restart()
    assert_receive {:DOWN, ^ref, :process, {Vehicles, :nonode@nohost}, :normal}

    refute_receive _
  end

  describe "uses fallback vehicles" do
    alias TeslaMate.Settings.CarSettings
    alias TeslaMate.{Log, Api}
    alias TeslaMate.Log.Car

    import Mock

    @tag :capture_log
    test "empty list" do
      {:ok, %Car{id: id}} =
        %Car{settings: %CarSettings{}}
        |> Car.changeset(%{vid: 333_333, eid: 2_222_222, vin: "1234"})
        |> Log.create_or_update_car()

      with_mock Api, list_vehicles: fn -> {:ok, []} end do
        {:ok, _pid} =
          start_supervised(
            {ApiMock, name: :api_vehicle, events: [{:ok, online_event()}], pid: self()}
          )

        {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock})

        assert true = Vehicles.Vehicle.healthy?(id)
      end
    end

    @tag :capture_log
    test "not signed in" do
      {:ok, %Car{id: id}} =
        %Car{settings: %CarSettings{}}
        |> Car.changeset(%{vid: 333_333, eid: 2_222_222, vin: "1234"})
        |> Log.create_or_update_car()

      with_mock Api, list_vehicles: fn -> {:error, :not_signed_in} end do
        {:ok, _pid} =
          start_supervised(
            {ApiMock, name: :api_vehicle, events: [{:ok, online_event()}], pid: self()}
          )

        {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock})

        assert true = Vehicles.Vehicle.healthy?(id)
      end
    end
  end
end
