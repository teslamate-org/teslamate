defmodule TeslaMate.LogTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log

  # describe "positions" do
  #   alias TeslaMate.Log.Position

  #   @valid_attrs %{name: "some name"}
  #   @update_attrs %{name: "some updated name"}
  #   @invalid_attrs %{name: nil}

  #   def position_fixture(attrs \\ %{}) do
  #     {:ok, position} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Log.create_position()

  #     position
  #   end

  #   test "list_positions/0 returns all positions" do
  #     position = position_fixture()
  #     assert Log.list_positions() == [position]
  #   end

  #   test "get_position!/1 returns the position with given id" do
  #     position = position_fixture()
  #     assert Log.get_position!(position.id) == position
  #   end

  #   test "create_position/1 with valid data creates a position" do
  #     assert {:ok, %Position{} = position} = Log.create_position(@valid_attrs)
  #     assert position.name == "some name"
  #   end

  #   test "create_position/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Log.create_position(@invalid_attrs)
  #   end

  #   test "update_position/2 with valid data updates the position" do
  #     position = position_fixture()
  #     assert {:ok, %Position{} = position} = Log.update_position(position, @update_attrs)
  #     assert position.name == "some updated name"
  #   end

  #   test "update_position/2 with invalid data returns error changeset" do
  #     position = position_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Log.update_position(position, @invalid_attrs)
  #     assert position == Log.get_position!(position.id)
  #   end

  #   test "delete_position/1 deletes the position" do
  #     position = position_fixture()
  #     assert {:ok, %Position{}} = Log.delete_position(position)
  #     assert_raise Ecto.NoResultsError, fn -> Log.get_position!(position.id) end
  #   end

  #   test "change_position/1 returns a position changeset" do
  #     position = position_fixture()
  #     assert %Ecto.Changeset{} = Log.change_position(position)
  #   end
  # end

  # describe "states" do
  #   alias TeslaMate.Log.State

  #   @valid_attrs %{end_date: "2010-04-17T14:00:00Z", end_position_id: 42, start_data: "2010-04-17T14:00:00Z", start_position_id: 42, state: "some state"}
  #   @update_attrs %{end_date: "2011-05-18T15:01:01Z", end_position_id: 43, start_data: "2011-05-18T15:01:01Z", start_position_id: 43, state: "some updated state"}
  #   @invalid_attrs %{end_date: nil, end_position_id: nil, start_data: nil, start_position_id: nil, state: nil}

  #   def state_fixture(attrs \\ %{}) do
  #     {:ok, state} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Log.create_state()

  #     state
  #   end

  #   test "list_states/0 returns all states" do
  #     state = state_fixture()
  #     assert Log.list_states() == [state]
  #   end

  #   test "get_state!/1 returns the state with given id" do
  #     state = state_fixture()
  #     assert Log.get_state!(state.id) == state
  #   end

  #   test "create_state/1 with valid data creates a state" do
  #     assert {:ok, %State{} = state} = Log.create_state(@valid_attrs)
  #     assert state.end_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert state.end_position_id == 42
  #     assert state.start_data == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert state.start_position_id == 42
  #     assert state.state == "some state"
  #   end

  #   test "create_state/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Log.create_state(@invalid_attrs)
  #   end

  #   test "update_state/2 with valid data updates the state" do
  #     state = state_fixture()
  #     assert {:ok, %State{} = state} = Log.update_state(state, @update_attrs)
  #     assert state.end_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert state.end_position_id == 43
  #     assert state.start_data == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert state.start_position_id == 43
  #     assert state.state == "some updated state"
  #   end

  #   test "update_state/2 with invalid data returns error changeset" do
  #     state = state_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Log.update_state(state, @invalid_attrs)
  #     assert state == Log.get_state!(state.id)
  #   end

  #   test "delete_state/1 deletes the state" do
  #     state = state_fixture()
  #     assert {:ok, %State{}} = Log.delete_state(state)
  #     assert_raise Ecto.NoResultsError, fn -> Log.get_state!(state.id) end
  #   end

  #   test "change_state/1 returns a state changeset" do
  #     state = state_fixture()
  #     assert %Ecto.Changeset{} = Log.change_state(state)
  #   end
  # end

  # describe "trips" do
  #   alias TeslaMate.Log.Trip

  #   @valid_attrs %{end_date: "2010-04-17T14:00:00Z", end_position_id: 42, start_date: "2010-04-17T14:00:00Z", start_position_id: 42}
  #   @update_attrs %{end_date: "2011-05-18T15:01:01Z", end_position_id: 43, start_date: "2011-05-18T15:01:01Z", start_position_id: 43}
  #   @invalid_attrs %{end_date: nil, end_position_id: nil, start_date: nil, start_position_id: nil}

  #   def trip_fixture(attrs \\ %{}) do
  #     {:ok, trip} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Log.create_trip()

  #     trip
  #   end

  #   test "list_trips/0 returns all trips" do
  #     trip = trip_fixture()
  #     assert Log.list_trips() == [trip]
  #   end

  #   test "get_trip!/1 returns the trip with given id" do
  #     trip = trip_fixture()
  #     assert Log.get_trip!(trip.id) == trip
  #   end

  #   test "create_trip/1 with valid data creates a trip" do
  #     assert {:ok, %Trip{} = trip} = Log.create_trip(@valid_attrs)
  #     assert trip.end_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert trip.end_position_id == 42
  #     assert trip.start_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert trip.start_position_id == 42
  #   end

  #   test "create_trip/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Log.create_trip(@invalid_attrs)
  #   end

  #   test "update_trip/2 with valid data updates the trip" do
  #     trip = trip_fixture()
  #     assert {:ok, %Trip{} = trip} = Log.update_trip(trip, @update_attrs)
  #     assert trip.end_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert trip.end_position_id == 43
  #     assert trip.start_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert trip.start_position_id == 43
  #   end

  #   test "update_trip/2 with invalid data returns error changeset" do
  #     trip = trip_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Log.update_trip(trip, @invalid_attrs)
  #     assert trip == Log.get_trip!(trip.id)
  #   end

  #   test "delete_trip/1 deletes the trip" do
  #     trip = trip_fixture()
  #     assert {:ok, %Trip{}} = Log.delete_trip(trip)
  #     assert_raise Ecto.NoResultsError, fn -> Log.get_trip!(trip.id) end
  #   end

  #   test "change_trip/1 returns a trip changeset" do
  #     trip = trip_fixture()
  #     assert %Ecto.Changeset{} = Log.change_trip(trip)
  #   end
  # end

  # describe "charging_states" do
  #   alias TeslaMate.Log.ChargingProcess

  #   @valid_attrs %{end_date: "2010-04-17T14:00:00Z", start_date: "2010-04-17T14:00:00Z"}
  #   @update_attrs %{end_date: "2011-05-18T15:01:01Z", start_date: "2011-05-18T15:01:01Z"}
  #   @invalid_attrs %{end_date: nil, start_date: nil}

  #   def charging_state_fixture(attrs \\ %{}) do
  #     {:ok, charging_state} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Log.create_charging_state()

  #     charging_state
  #   end

  #   test "list_charging_states/0 returns all charging_states" do
  #     charging_state = charging_state_fixture()
  #     assert Log.list_charging_states() == [charging_state]
  #   end

  #   test "get_charging_state!/1 returns the charging_state with given id" do
  #     charging_state = charging_state_fixture()
  #     assert Log.get_charging_state!(charging_state.id) == charging_state
  #   end

  #   test "create_charging_state/1 with valid data creates a charging_state" do
  #     assert {:ok, %ChargingProcess{} = charging_state} = Log.create_charging_state(@valid_attrs)
  #     assert charging_state.end_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert charging_state.start_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #   end

  #   test "create_charging_state/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Log.create_charging_state(@invalid_attrs)
  #   end

  #   test "update_charging_state/2 with valid data updates the charging_state" do
  #     charging_state = charging_state_fixture()
  #     assert {:ok, %ChargingProcess{} = charging_state} = Log.update_charging_state(charging_state, @update_attrs)
  #     assert charging_state.end_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert charging_state.start_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #   end

  #   test "update_charging_state/2 with invalid data returns error changeset" do
  #     charging_state = charging_state_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Log.update_charging_state(charging_state, @invalid_attrs)
  #     assert charging_state == Log.get_charging_state!(charging_state.id)
  #   end

  #   test "delete_charging_state/1 deletes the charging_state" do
  #     charging_state = charging_state_fixture()
  #     assert {:ok, %ChargingProcess{}} = Log.delete_charging_state(charging_state)
  #     assert_raise Ecto.NoResultsError, fn -> Log.get_charging_state!(charging_state.id) end
  #   end

  #   test "change_charging_state/1 returns a charging_state changeset" do
  #     charging_state = charging_state_fixture()
  #     assert %Ecto.Changeset{} = Log.change_charging_state(charging_state)
  #   end
  # end

  # describe "charges" do
  #   alias TeslaMate.Log.Charge

  #   @valid_attrs %{battery_level: 120.5, charge_energy_added: 120.5, charger_actual_current: 42, charger_phases: 42, charger_power: 120.5, charger_voltage: 42, date: "2010-04-17T14:00:00Z", ideal_battery_range_km: 120.5, outside_temp: 120.5}
  #   @update_attrs %{battery_level: 456.7, charge_energy_added: 456.7, charger_actual_current: 43, charger_phases: 43, charger_power: 456.7, charger_voltage: 43, date: "2011-05-18T15:01:01Z", ideal_battery_range_km: 456.7, outside_temp: 456.7}
  #   @invalid_attrs %{battery_level: nil, charge_energy_added: nil, charger_actual_current: nil, charger_phases: nil, charger_power: nil, charger_voltage: nil, date: nil, ideal_battery_range_km: nil, outside_temp: nil}

  #   def charge_fixture(attrs \\ %{}) do
  #     {:ok, charge} =
  #       attrs
  #       |> Enum.into(@valid_attrs)
  #       |> Log.create_charge()

  #     charge
  #   end

  #   test "list_charges/0 returns all charges" do
  #     charge = charge_fixture()
  #     assert Log.list_charges() == [charge]
  #   end

  #   test "get_charge!/1 returns the charge with given id" do
  #     charge = charge_fixture()
  #     assert Log.get_charge!(charge.id) == charge
  #   end

  #   test "create_charge/1 with valid data creates a charge" do
  #     assert {:ok, %Charge{} = charge} = Log.create_charge(@valid_attrs)
  #     assert charge.battery_level == 120.5
  #     assert charge.charge_energy_added == 120.5
  #     assert charge.charger_actual_current == 42
  #     assert charge.charger_phases == 42
  #     assert charge.charger_power == 120.5
  #     assert charge.charger_voltage == 42
  #     assert charge.date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
  #     assert charge.ideal_battery_range_km == 120.5
  #     assert charge.outside_temp == 120.5
  #   end

  #   test "create_charge/1 with invalid data returns error changeset" do
  #     assert {:error, %Ecto.Changeset{}} = Log.create_charge(@invalid_attrs)
  #   end

  #   test "update_charge/2 with valid data updates the charge" do
  #     charge = charge_fixture()
  #     assert {:ok, %Charge{} = charge} = Log.update_charge(charge, @update_attrs)
  #     assert charge.battery_level == 456.7
  #     assert charge.charge_energy_added == 456.7
  #     assert charge.charger_actual_current == 43
  #     assert charge.charger_phases == 43
  #     assert charge.charger_power == 456.7
  #     assert charge.charger_voltage == 43
  #     assert charge.date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
  #     assert charge.ideal_battery_range_km == 456.7
  #     assert charge.outside_temp == 456.7
  #   end

  #   test "update_charge/2 with invalid data returns error changeset" do
  #     charge = charge_fixture()
  #     assert {:error, %Ecto.Changeset{}} = Log.update_charge(charge, @invalid_attrs)
  #     assert charge == Log.get_charge!(charge.id)
  #   end

  #   test "delete_charge/1 deletes the charge" do
  #     charge = charge_fixture()
  #     assert {:ok, %Charge{}} = Log.delete_charge(charge)
  #     assert_raise Ecto.NoResultsError, fn -> Log.get_charge!(charge.id) end
  #   end

  #   test "change_charge/1 returns a charge changeset" do
  #     charge = charge_fixture()
  #     assert %Ecto.Changeset{} = Log.change_charge(charge)
  #   end
  # end

  describe "car" do
    alias TeslaMate.Log.Car

    @valid_attrs %{efficiency: 120.5, eid: 42, model: "some model", vid: 42}
    @update_attrs %{
      efficiency: 456.7,
      model: "some updated model",
      eid: 43,
      vid: 43
    }
    @invalid_attrs %{efficiency: nil, eid: nil, model: nil, vid: nil}

    def car_fixture(attrs \\ %{}) do
      {:ok, car} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Log.create_car()

      car
    end

    test "list_cars/0 returns all car" do
      car = car_fixture()
      assert Log.list_cars() == [car]
    end

    test "get_car!/1 returns the car with given id" do
      car = car_fixture()
      assert Log.get_car!(car.id) == car
    end

    test "create_car/1 with valid data creates a car" do
      assert {:ok, %Car{} = car} = Log.create_car(@valid_attrs)
      assert car.efficiency == 120.5
      assert car.eid == 42
      assert car.model == "some model"
      assert car.vid == 42
    end

    test "create_car/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Log.create_car(@invalid_attrs)
    end

    test "update_car/2 with valid data updates the car" do
      car = car_fixture()
      assert {:ok, %Car{} = car} = Log.update_car(car, @update_attrs)

      assert car.efficiency == 456.7
      assert car.model == "some updated model"

      assert car.eid == 42
      assert car.vid == 42
    end

    test "update_car/2 with invalid data returns error changeset" do
      car = car_fixture()
      assert {:error, %Ecto.Changeset{}} = Log.update_car(car, @invalid_attrs)
      assert car == Log.get_car!(car.id)
    end
  end
end
