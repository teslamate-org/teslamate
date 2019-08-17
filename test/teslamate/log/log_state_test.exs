defmodule TeslaMate.LogStateTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{State, Car}
  alias TeslaMate.Log

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42})
      |> Log.create_car()

    car
  end

  describe "create_state/1 " do
    test "with valid data creates a state" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, %State{} = state} = Log.start_state(car_id, :online)
      assert state.car_id == car_id
      assert %DateTime{} = state.start_date
      assert state.end_date == nil
      assert state.state == :online
    end

    test "does not create a new state if the state is already open" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, %State{state: :online, start_date: start_date, end_date: nil}} =
               Log.start_state(car_id, :online)

      assert {:ok, %State{state: :online, start_date: ^start_date, end_date: nil}} =
               Log.start_state(car_id, :online)
    end

    test "closes the previous state if the state changed" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, %State{state: :online, start_date: start_date, end_date: nil}} =
               Log.start_state(car_id, :online)

      :timer.sleep(10)

      assert {:ok, %State{state: :offline, start_date: end_date, end_date: nil}} =
               Log.start_state(car_id, :offline)

      assert [
               %State{state: :online, start_date: ^start_date, end_date: ^end_date},
               %State{state: :offline, start_date: ^end_date, end_date: nil}
             ] = Repo.all(State)
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(404, :foo)
      assert errors_on(changeset) == %{state: ["is invalid"]}

      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(404, :asleep)
      assert errors_on(changeset) == %{car_id: ["does not exist"]}
    end
  end
end
