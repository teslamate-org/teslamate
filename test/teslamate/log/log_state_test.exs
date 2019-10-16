defmodule TeslaMate.LogStateTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{State, Car}
  alias TeslaMate.Log

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
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

    test "completes the previous state if the state changed" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, %State{state: :online, start_date: start_date, end_date: nil}} =
               Log.start_state(car_id, :online)

      {:ok, %State{start_date: end_date}} =
        TestHelper.eventually(
          fn ->
            assert {:ok, %State{state: :offline, end_date: nil}} =
                     Log.start_state(car_id, :offline)
          end,
          delay: 10
        )

      assert [
               %State{state: :online, start_date: ^start_date, end_date: ^end_date},
               %State{state: :offline, start_date: ^end_date, end_date: nil}
             ] = Repo.all(State)
    end

    test "handles multiple cars" do
      assert %Car{id: car_id} = car_fixture()
      assert %Car{id: another_car_id} = car_fixture(eid: 43, vid: 43, vin: "yyyyy")

      assert {:ok, %State{state: :online, start_date: s0, end_date: nil}} =
               Log.start_state(car_id, :online)

      Process.sleep(10)

      assert {:ok, %State{state: :online, start_date: s1, end_date: nil}} =
               Log.start_state(another_car_id, :online)

      Process.sleep(10)

      assert {:ok, %State{state: :asleep, start_date: e1, end_date: nil}} =
               Log.start_state(another_car_id, :asleep)

      Process.sleep(10)

      assert {:ok, %State{state: :offline, start_date: e0, end_date: nil}} =
               Log.start_state(car_id, :offline)

      assert [
               %State{state: :online, start_date: ^s0, end_date: ^e0},
               %State{state: :online, start_date: ^e1, end_date: ^e1},
               %State{state: :asleep, start_date: ^s1, end_date: nil},
               %State{state: :offline, start_date: ^s0, end_date: nil}
             ] = State |> order_by(asc: :id) |> Repo.all()
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(404, :foo)
      assert errors_on(changeset) == %{state: ["is invalid"]}

      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(404, :asleep)
      assert errors_on(changeset) == %{car_id: ["does not exist"]}
    end
  end
end
