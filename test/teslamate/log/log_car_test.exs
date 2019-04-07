defmodule TeslaMate.LogCarTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.Car
  alias TeslaMate.Log

  @valid_attrs %{efficiency: 0.153, eid: 42, model: "M3", vid: 42}
  @update_attrs %{efficiency: 0.190, model: "MS", eid: 43, vid: 43}
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
    assert car.efficiency == 0.153
    assert car.eid == 42
    assert car.model == "M3"
    assert car.vid == 42
  end

  test "create_car/1 with invalid data returns error changeset" do
    assert {:error, %Ecto.Changeset{}} = Log.create_car(@invalid_attrs)
  end

  test "update_car/2 with valid data updates the car" do
    car = car_fixture()
    assert {:ok, %Car{} = car} = Log.update_car(car, @update_attrs)

    assert car.efficiency == 0.190
    assert car.model == "MS"
    assert car.eid == 42
    assert car.vid == 42
  end

  test "update_car/2 with invalid data returns error changeset" do
    car = car_fixture()
    assert {:error, %Ecto.Changeset{}} = Log.update_car(car, @invalid_attrs)
    assert car == Log.get_car!(car.id)
  end
end
