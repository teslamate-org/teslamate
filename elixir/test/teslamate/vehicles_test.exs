defmodule TeslaMate.VehiclesTest do
  use TeslaMate.VehicleCase
  use TeslaMate.DataCase

  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.Vehicles
  alias TeslaMate.Log

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

    assert :ok = Vehicles.restart()
    assert_receive {:DOWN, ^ref, :process, {Vehicles, :nonode@nohost}, :normal}
    assert_receive {ApiMock, {:stream, 4040, _}}

    refute_receive _
  end

  test "list/0 sorts by the current display order in the database" do
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
           %TeslaApi.Vehicle{display_name: "a", id: 1001, vehicle_id: 2001, vin: "aaaaaaa"},
           %TeslaApi.Vehicle{display_name: "b", id: 1002, vehicle_id: 2002, vin: "bbbbbbb"}
         ]}
      )

    assert_receive {ApiMock, {:stream, 2001, _}}
    assert_receive {ApiMock, {:stream, 2002, _}}

    assert ["aaaaaaa", "bbbbbbb"] == Enum.map(Vehicles.list(), & &1.car.vin)

    # The vehicle processes keep the car they loaded at start
    {:ok, _car} = Log.get_car_by(vin: "aaaaaaa") |> Log.update_car(%{display_priority: 2})

    assert ["bbbbbbb", "aaaaaaa"] == Enum.map(Vehicles.list(), & &1.car.vin)
  end

  describe "discover/0" do
    import Mock

    alias TeslaMate.{Api, Log}
    alias TeslaMate.Log.Car
    alias TeslaMate.Settings.CarSettings

    @first %TeslaApi.Vehicle{display_name: "first", id: 1001, vehicle_id: 2001, vin: "VIN1"}
    @second %TeslaApi.Vehicle{display_name: "second", id: 1002, vehicle_id: 2002, vin: "VIN2"}

    setup do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
        )

      {:ok, answer} = Agent.start_link(fn -> {:ok, []} end)
      :ok = Vehicles.subscribe()

      [answer: answer, list_vehicles: fn -> Agent.get(answer, & &1) end]
    end

    defp answer(agent, value), do: Agent.update(agent, fn _ -> value end)

    defp running_pid(%Car{id: id}), do: Process.whereis(:"#{id}")

    test "starts a logger for a new vehicle and announces it", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      :ok = answer(answer, {:ok, [@first]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, [%Car{vin: "VIN1"} = car]} = Vehicles.discover()
        assert is_pid(running_pid(car))
        assert_receive {ApiMock, {:stream, 2001, _}}
        assert_receive {Vehicles, :vehicles_changed}
        assert [%Vehicle.Summary{car: %Car{vin: "VIN1"}}] = Vehicles.list()
      end
    end

    test "leaves running loggers untouched and is idempotent", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: [@first]})
      assert_receive {ApiMock, {:stream, 2001, _}}
      [%Vehicle.Summary{car: first}] = Vehicles.list()
      first_pid = running_pid(first)

      :ok = answer(answer, {:ok, [@first, @second]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, [%Car{vin: "VIN2"}]} = Vehicles.discover()
        assert_receive {Vehicles, :vehicles_changed}
        assert running_pid(first) == first_pid
        assert_receive {ApiMock, {:stream, 2002, _}}

        assert {:ok, []} = Vehicles.discover()
        refute_receive {Vehicles, :vehicles_changed}
        assert running_pid(first) == first_pid
        assert length(Vehicles.list()) == 2
      end
    end

    test "skips vehicles with data collection disabled", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx

      {:ok, %Car{} = car} =
        %Car{settings: %CarSettings{enabled: false}}
        |> Car.changeset(%{vid: 2001, eid: 1001, vin: "VIN1"})
        |> Log.create_or_update_car()

      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      :ok = answer(answer, {:ok, [@first]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, []} = Vehicles.discover()
        assert nil == running_pid(car)
        refute_receive {Vehicles, :vehicles_changed}
      end
    end

    test "returns each error of the API call", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        :ok = answer(answer, {:ok, []})
        assert {:error, :no_vehicles} = Vehicles.discover()

        :ok = answer(answer, {:error, :not_signed_in})
        assert {:error, :not_signed_in} = Vehicles.discover()

        :ok = answer(answer, {:error, :too_many_request, 30})
        assert {:error, :too_many_request} = Vehicles.discover()

        :ok = answer(answer, {:error, :timeout})
        assert {:error, :timeout} = Vehicles.discover()

        refute_receive {Vehicles, :vehicles_changed}
      end
    end

    test "returns a database error to the caller and keeps the loggers", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: [@first]})
      assert_receive {ApiMock, {:stream, 2001, _}}
      [%Vehicle.Summary{car: first}] = Vehicles.list()
      first_pid = running_pid(first)
      owner = Process.whereis(Vehicles)

      # A vehicle without a VIN fails the changeset
      :ok = answer(answer, {:ok, [%TeslaApi.Vehicle{@second | vin: nil}]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:error, %Ecto.Changeset{errors: [vin: _]}} = Vehicles.discover()
        assert Process.whereis(Vehicles) == owner
        assert running_pid(first) == first_pid
        refute_receive {Vehicles, :vehicles_changed}
      end
    end

    test "announces loggers started before a later vehicle failed", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      :ok = answer(answer, {:ok, [@first, %TeslaApi.Vehicle{@second | vin: nil}]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:error, %Ecto.Changeset{}} = Vehicles.discover()
        assert_receive {Vehicles, :vehicles_changed}
        assert [%Vehicle.Summary{car: %Car{vin: "VIN1"}}] = Vehicles.list()
      end
    end

    test "picks up a car inserted by a concurrent discovery", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      :ok = answer(answer, {:ok, [@first]})
      {:ok, _} = Log.create_car(%{name: "first", eid: 1001, vid: 2001, vin: "VIN1"})

      # The three lookups before the insert see no car yet (the other
      # discovery inserts it in between), so the insert hits the constraint
      {:ok, lookups} = Agent.start_link(fn -> 0 end)

      get_car_by = fn opts ->
        if Agent.get_and_update(lookups, &{&1, &1 + 1}) < 3,
          do: nil,
          else: :meck.passthrough([opts])
      end

      with_mocks [
        {Api, [:passthrough], list_vehicles: list_vehicles},
        {Log, [:passthrough], get_car_by: get_car_by}
      ] do
        assert {:ok, [%Car{vin: "VIN1"}]} = Vehicles.discover()
        assert length(Log.list_cars()) == 1
        # three lookups before the failed insert, one that finds the car
        assert Agent.get(lookups, & &1) == 4
      end
    end

    test "treats a vehicle between restarts as running", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: [@first]})
      assert_receive {ApiMock, {:stream, 2001, _}}
      supervisor = GenServer.call(Vehicles, :supervisor)
      [{child_id, _pid, _type, _modules}] = Supervisor.which_children(supervisor)

      # Spec present, child not running: as during a restart loop
      :ok = Supervisor.terminate_child(supervisor, child_id)
      :ok = answer(answer, {:ok, [@first]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, []} = Vehicles.discover()
        refute_receive {Vehicles, :vehicles_changed}
        assert [{^child_id, :undefined, _, _}] = Supervisor.which_children(supervisor)
      end
    end

    test "concurrent discoveries start every vehicle exactly once", ctx do
      %{answer: answer, list_vehicles: list_vehicles} = ctx
      {:ok, _} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      :ok = answer(answer, {:ok, [@first, @second]})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        results =
          1..4
          |> Enum.map(fn _ -> Task.async(&Vehicles.discover/0) end)
          |> Task.await_many()

        assert Enum.all?(results, &match?({:ok, _}, &1))
        started = for {:ok, cars} <- results, car <- cars, do: car.vin
        assert Enum.sort(started) == ["VIN1", "VIN2"]
        assert length(Vehicles.list()) == 2
        assert length(Log.list_cars()) == 2
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
