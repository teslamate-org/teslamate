defmodule TeslaMate.LogCarTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.Car
  alias TeslaMate.Log

  @valid_attrs %{
    efficiency: 0.153,
    eid: 42,
    model: "S",
    vid: 42,
    name: "foo",
    trim_badging: "P100D",
    vin: "12345F"
  }
  @update_attrs %{
    efficiency: 0.190,
    model: "S",
    eid: 43,
    vid: 43,
    name: "bar",
    trim_badging: "100D",
    vin: "6789R"
  }
  @invalid_attrs %{
    efficiency: nil,
    eid: nil,
    model: nil,
    vid: nil,
    name: 1,
    trim_badging: 2,
    vin: 3
  }

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

  test "create_or_update_car/1 with valid data creates a car" do
    assert {:ok, %Car{} = car} =
             Car.changeset(%Car{eid: @valid_attrs.eid, vid: @valid_attrs.vid}, @valid_attrs)
             |> Log.create_or_update_car()

    assert car.efficiency == 0.153
    assert car.eid == 42
    assert car.model == "S"
    assert car.vid == 42
    assert car.name == "foo"
    assert car.trim_badging == "P100D"
    assert car.vin == "12345F"
  end

  test "create_or_update_car/1 with invalid data returns error changeset" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             Car.changeset(%Car{}, @invalid_attrs) |> Log.create_or_update_car()

    assert %{
             eid: ["can't be blank"],
             name: ["is invalid"],
             trim_badging: ["is invalid"],
             vid: ["can't be blank"],
             vin: ["is invalid"]
           } == errors_on(changeset)
  end

  test "create_or_update_car/2 with valid data updates the car" do
    car = car_fixture()

    assert {:ok, %Car{} = car} = Car.changeset(car, @update_attrs) |> Log.create_or_update_car()

    assert car.efficiency == 0.190
    assert car.model == "S"
    assert car.eid == 43
    assert car.vid == 43
    assert car.name == "bar"
    assert car.trim_badging == "100D"
    assert car.vin == "6789R"
  end

  test "create_or_update_car/2 with invalid data returns error changeset" do
    car = car_fixture()

    assert {:error, %Ecto.Changeset{}} =
             Car.changeset(car, @invalid_attrs) |> Log.create_or_update_car()

    assert car == Log.get_car!(car.id)
  end
end
