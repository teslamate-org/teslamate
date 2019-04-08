defmodule TeslaMate.LogUpdateTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, Update}
  alias TeslaMate.Log

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42})
      |> Log.create_car()

    car
  end

  describe "start_update/2" do
    test "creates an update entry with a start_date" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, update_id} = Log.start_update(car_id)

      assert %Update{car_id: ^car_id, start_date: %DateTime{}} = Repo.get(Update, update_id)
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_update(nil)
      assert errors_on(changeset) == %{car_id: ["can't be blank"]}
    end
  end

  describe "finish_update/1" do
    test "closes charging process with zero charges " do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, update_id} = Log.start_update(car_id)

      version = "2019.8.5 3aaa23d"
      assert {:ok, %Update{} = update} = Log.finish_update(update_id, version)

      assert %DateTime{} = update.start_date
      assert %DateTime{} = update.end_date
      assert update.version == version
    end
  end
end
