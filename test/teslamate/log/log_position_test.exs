defmodule TeslaMate.LogPositionTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end

  describe "get_latest_position/1" do
    test "returns the latest complete position for a car" do
      car = car_fixture()
      other_car = car_fixture(eid: 43, vid: 43, vin: "yyyyy")

      {:ok, complete_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:00:00Z],
          latitude: 1.0,
          longitude: 1.0,
          ideal_battery_range_km: 300.0
        })

      {:ok, _incomplete_streaming_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:05:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      {:ok, _other_car_position} =
        Log.insert_position(other_car, %{
          date: ~U[2026-01-01 10:10:00Z],
          latitude: 3.0,
          longitude: 3.0,
          ideal_battery_range_km: 200.0
        })

      assert %{id: id} = Log.get_latest_position(car)
      assert id == complete_position.id
    end

    test "returns nil when a car only has incomplete streaming positions" do
      car = car_fixture()

      {:ok, _incomplete_streaming_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:05:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      assert Log.get_latest_position(car) == nil
    end
  end

  describe "get_last_inserted_position/0" do
    test "returns the most recently inserted position across all cars, including incomplete ones" do
      car = car_fixture()
      other_car = car_fixture(eid: 43, vid: 43, vin: "yyyyy")

      {:ok, _latest_by_date_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:00:00Z],
          latitude: 1.0,
          longitude: 1.0,
          ideal_battery_range_km: 300.0
        })

      {:ok, latest_position} =
        Log.insert_position(other_car, %{
          date: ~U[2026-01-01 09:55:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      assert %{id: id} = Log.get_last_inserted_position()
      assert id == latest_position.id
    end
  end
end
