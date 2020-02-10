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
      car = car_fixture()
      assert {:ok, %State{} = state} = Log.start_state(car, :online)
      assert state.car_id == car.id
      assert %DateTime{} = state.start_date
      assert state.end_date == nil
      assert state.state == :online
    end

    test "does not create a new state if the state is already open" do
      car = car_fixture()

      assert {:ok, %State{state: :online, start_date: start_date, end_date: nil}} =
               Log.start_state(car, :online)

      assert {:ok, %State{state: :online, start_date: ^start_date, end_date: nil}} =
               Log.start_state(car, :online)
    end

    test "completes the previous state if the state changed" do
      car = car_fixture()

      assert {:ok, %State{state: :online, start_date: start_date, end_date: nil}} =
               Log.start_state(car, :online)

      {:ok, %State{start_date: end_date}} =
        TestHelper.eventually(
          fn ->
            assert {:ok, %State{state: :offline, end_date: nil}} = Log.start_state(car, :offline)
          end,
          delay: 10
        )

      assert [
               %State{state: :online, start_date: ^start_date, end_date: ^end_date},
               %State{state: :offline, start_date: ^end_date, end_date: nil}
             ] = Repo.all(State)
    end

    test "handles multiple cars" do
      car = car_fixture()

      another_car = car_fixture(eid: 43, vid: 43, vin: "yyyyy")

      assert {:ok, %State{state: :online, start_date: s0, end_date: nil}} =
               Log.start_state(car, :online)

      assert {:ok, %State{state: :online, start_date: s1, end_date: nil}} =
               Log.start_state(another_car, :online)

      Process.sleep(1010)

      assert {:ok, %State{state: :asleep, start_date: e1, end_date: nil}} =
               Log.start_state(another_car, :asleep)

      assert {:ok, %State{state: :offline, start_date: e0, end_date: nil}} =
               Log.start_state(car, :offline)

      assert [state_0, state_1, state_2, state_3] = State |> order_by(asc: :id) |> Repo.all()
      assert %State{state: :online, start_date: ^s0, end_date: ^e0} = state_0
      assert %State{state: :online, start_date: ^s1, end_date: ^e1} = state_1
      assert %State{state: :asleep, start_date: ^e1, end_date: nil} = state_2
      assert %State{state: :offline, start_date: ^e0, end_date: nil} = state_3
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(%Car{id: 404}, :foo)
      assert errors_on(changeset) == %{state: ["is invalid"]}

      assert {:error, %Ecto.Changeset{} = changeset} = Log.start_state(%Car{id: 404}, :asleep)
      assert errors_on(changeset) == %{car_id: ["does not exist"]}
    end
  end
end
