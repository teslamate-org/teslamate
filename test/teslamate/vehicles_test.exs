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

  describe "car settings" do
    alias TeslaApi.Vehicle.State.VehicleConfig
    alias TeslaMate.{Log, Repo}

    import Ecto.Query

    @tag :capture_log
    test "lowers the suspend min for vehicles with modern MCU" do
      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event()}], pid: self()}
        )

      {:ok, _pid} =
        start_supervised({Vehicles,
         vehicle: VehicleMock,
         vehicles: [
           %TeslaApi.Vehicle{
             display_name: "S LR",
             id: 999_001,
             vehicle_id: 999_001,
             vin: "999001",
             vehicle_config: %VehicleConfig{car_type: "models2", trim_badging: nil}
           },
           %TeslaApi.Vehicle{
             display_name: "3 AWD",
             id: 999_003,
             vehicle_id: 999_003,
             vin: "999003",
             vehicle_config: %VehicleConfig{car_type: "model3", trim_badging: nil}
           },
           %TeslaApi.Vehicle{
             display_name: "X LR",
             id: 999_002,
             vehicle_id: 999_002,
             vin: "999002",
             vehicle_config: %VehicleConfig{car_type: "modelx", trim_badging: nil}
           },
           %TeslaApi.Vehicle{
             display_name: "Y",
             id: 999_004,
             vehicle_id: 999_004,
             vin: "999004",
             vehicle_config: %VehicleConfig{car_type: "modely", trim_badging: nil}
           },
           # ---------------------------------------------------------------------
           %TeslaApi.Vehicle{
             display_name: "S",
             id: 999_005,
             vehicle_id: 999_005,
             vin: "999005",
             vehicle_config: %VehicleConfig{car_type: "models", trim_badging: "p100d"}
           },
           %TeslaApi.Vehicle{
             display_name: "X",
             id: 999_006,
             vehicle_id: 999_006,
             vin: "999006",
             vehicle_config: %VehicleConfig{car_type: "modelx", trim_badging: "p100d"}
           },
           # ---------------------------------------------------------------------
           %TeslaApi.Vehicle{
             display_name: "asleep",
             id: 999_007,
             vehicle_id: 999_007,
             vin: "999007",
             vehicle_config: nil
           }
         ]})

      assert [s, e, x, y | rest] =
               from(c in Log.Car, preload: :settings, order_by: :id)
               |> Repo.all()

      assert s.settings.suspend_min == 12
      assert e.settings.suspend_min == 12
      assert x.settings.suspend_min == 12
      assert y.settings.suspend_min == 12
      # ---------------------------------
      assert [s, x | rest] = rest
      assert s.settings.suspend_min == 21
      assert x.settings.suspend_min == 21
      # ---------------------------------
      assert [asleep] = rest
      assert asleep.settings.suspend_min == 21
    end
  end
end
