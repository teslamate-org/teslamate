defmodule TeslaMate.LogChargingCostSyncTest do
  use TeslaMate.DataCase, async: true

  alias TeslaApi.ChargingHistory.Session
  alias TeslaMate.Log.{ChargingProcess}
  alias TeslaMate.{Log, Repo}

  defp car_fixture do
    id = System.unique_integer([:positive])
    {:ok, car} = Log.create_car(%{eid: id, vid: id, vin: "VIN-#{id}"})
    car
  end

  defp charging_process_fixture(car, start_date, attrs \\ %{}) do
    {:ok, charging_process} =
      Log.start_charging_process(
        car,
        %{date: start_date, latitude: 0.0, longitude: 0.0},
        lookup_address: false
      )

    charging_process
    |> ChargingProcess.changeset(Map.put(attrs, :start_date, start_date))
    |> Repo.update!()
  end

  test "matches by VIN window and uses energy before time as the tiebreaker" do
    car = car_fixture()
    start_date = ~U[2026-08-01 10:00:00.000000Z]

    near =
      charging_process_fixture(car, DateTime.add(start_date, -30), %{
        charge_energy_added: Decimal.new(10)
      })

    energy_match =
      charging_process_fixture(car, DateTime.add(start_date, 30), %{
        charge_energy_added: Decimal.new(40)
      })

    session = %Session{
      start_date: start_date,
      energy: Decimal.new(40),
      cost: Decimal.new("12.34")
    }

    assert {:ok, id} = Log.sync_charging_cost(car, session)
    assert id == energy_match.id
    assert Repo.reload!(near).cost == nil
    assert Decimal.equal?(Repo.reload!(energy_match).cost, Decimal.new("12.34"))
  end

  test "falls back to thirty minutes and stores an explicit zero" do
    car = car_fixture()
    start_date = ~U[2026-08-01 10:00:00.000000Z]
    charging_process = charging_process_fixture(car, DateTime.add(start_date, 20 * 60, :second))

    assert {:ok, id} =
             Log.sync_charging_cost(car, %Session{
               start_date: start_date,
               cost: Decimal.new(0)
             })

    assert id == charging_process.id
    assert Decimal.equal?(Repo.reload!(charging_process).cost, Decimal.new(0))
  end

  test "does not overwrite existing costs or match a different vehicle" do
    car = car_fixture()
    other_car = car_fixture()
    start_date = ~U[2026-08-01 10:00:00.000000Z]

    existing =
      charging_process_fixture(car, start_date, %{
        cost: Decimal.new(5)
      })

    charging_process_fixture(other_car, start_date)

    assert :no_match =
             Log.sync_charging_cost(car, %Session{
               start_date: start_date,
               cost: Decimal.new(10)
             })

    assert Decimal.equal?(Repo.reload!(existing).cost, Decimal.new(5))
  end

  test "ignores incomplete API sessions" do
    car = car_fixture()
    assert :ignored = Log.sync_charging_cost(car, %Session{start_date: DateTime.utc_now()})
    assert :ignored = Log.sync_charging_cost(car, %Session{cost: Decimal.new(1)})
  end
end
