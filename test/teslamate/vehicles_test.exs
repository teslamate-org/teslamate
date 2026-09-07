defmodule TeslaMate.VehiclesTest do
  use TeslaMate.VehicleCase
  use TeslaMate.DataCase

  alias TeslaMate.Vehicles.Vehicle
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
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    {:ok, _pid} =
      start_supervised(
        {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
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

    assert_receive {ApiMock, {:stream, 4040, _}}

    ref = Process.monitor(Vehicles)
    :ok = Vehicles.subscribe()

    assert :ok = Vehicles.restart()
    assert_receive {:DOWN, ^ref, :process, {Vehicles, :nonode@nohost}, :shutdown}
    assert_receive {ApiMock, {:stream, 4040, _}}
    assert_receive {Vehicles, :reloaded}

    refute_receive _
  end

  test "restart/0 does not count toward the parent's restart intensity" do
    parent = %{
      id: :parent,
      start:
        {Supervisor, :start_link,
         [[{Vehicles, vehicles: []}], [strategy: :one_for_one, max_restarts: 1, max_seconds: 60]]},
      type: :supervisor
    }

    {:ok, parent_pid} = start_supervised(parent)

    for _ <- 1..5, do: assert(:ok = Vehicles.restart())

    assert Process.alive?(parent_pid)
    assert is_pid(Process.whereis(Vehicles))
  end

  test "restart/0 reports a supervisor that is not running" do
    assert nil == Process.whereis(Vehicles)
    assert {:error, :not_running} = Vehicles.restart()
  end

  test "list/0 is empty while the supervisor is not running" do
    assert nil == Process.whereis(Vehicles)
    assert [] = Vehicles.list()
  end

  describe "discovery_result/0" do
    alias TeslaMate.Api

    import Mock

    test "is :ok when the vehicles are given" do
      {:ok, _} = start_supervised({Vehicles, vehicles: []})
      assert :ok = Vehicles.discovery_result()
    end

    @tag :capture_log
    test "reports an account without vehicles" do
      with_mock Api, list_vehicles: fn -> {:ok, []} end do
        {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock})
        assert {:error, :no_vehicles} = Vehicles.discovery_result()
      end
    end

    @tag :capture_log
    test "reports a rate limited API" do
      with_mock Api, list_vehicles: fn -> {:error, :too_many_request, 30} end do
        {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock})
        assert {:error, :too_many_request} = Vehicles.discovery_result()
      end
    end

    @tag :capture_log
    test "reports a failed API call" do
      with_mock Api, list_vehicles: fn -> {:error, :timeout} end do
        {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock})
        assert {:error, :timeout} = Vehicles.discovery_result()
      end
    end

    @tag :capture_log
    test "reports a signed out API" do
      with_mock Api, list_vehicles: fn -> {:error, :not_signed_in} end do
        {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock})
        assert {:error, :not_signed_in} = Vehicles.discovery_result()
      end
    end
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
        now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

        {:ok, _pid} =
          start_supervised(
            {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
          )

        {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock})

        assert true = Vehicle.healthy?(id)
      end
    end

    @tag :capture_log
    test "not signed in" do
      {:ok, %Car{id: id}} =
        %Car{settings: %CarSettings{}}
        |> Car.changeset(%{vid: 333_333, eid: 2_222_222, vin: "1234"})
        |> Log.create_or_update_car()

      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      with_mock Api, list_vehicles: fn -> {:error, :not_signed_in} end do
        {:ok, _pid} =
          start_supervised(
            {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
          )

        start_supervised!({Vehicles, vehicle: VehicleMock})

        assert true = Vehicle.healthy?(id)
      end
    end
  end

  describe "car settings" do
    alias TeslaMate.Settings.CarSettings
    alias TeslaApi.Vehicle.State.VehicleConfig
    alias TeslaMate.{Log, Repo}
    alias TeslaMate.Vehicles.Vehicle.Summary

    import Ecto.Query

    @tag :capture_log
    test "lowers the suspend min for vehicles with modern MCU" do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
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
             vehicle_config: %VehicleConfig{car_type: "tamarind", trim_badging: "P100D"}
           },
           %TeslaApi.Vehicle{
             display_name: "Y",
             id: 999_004,
             vehicle_id: 999_004,
             vin: "999004",
             vehicle_config: %VehicleConfig{car_type: "modely", trim_badging: nil}
           },
           %TeslaApi.Vehicle{
             display_name: "Cybertruck",
             id: 999_008,
             vehicle_id: 999_008,
             vin: "999008",
             vehicle_config: %VehicleConfig{car_type: "cybertruck", trim_badging: "foundation"}
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

      assert [s, e, x, y, cybertruck | rest] =
               from(c in Log.Car, preload: :settings, order_by: :id)
               |> Repo.all()

      assert_suspend_min(s, 12)
      assert_suspend_min(e, 12)
      assert_suspend_min(x, 12)
      assert_suspend_min(y, 12)
      assert_suspend_min(cybertruck, 12)
      # ---------------------------------
      assert [s, x | rest] = rest
      assert_suspend_min(s, 21)
      assert_suspend_min(x, 21)
      # ---------------------------------
      assert [asleep] = rest
      assert_suspend_min(asleep, 21)
    end

    defp assert_suspend_min(car, suspend_min) do
      assert car.settings.suspend_min == suspend_min

      assert %Summary{car: %Log.Car{settings: %CarSettings{suspend_min: ^suspend_min}}} =
               Vehicle.summary(car.id)
    end
  end
end
