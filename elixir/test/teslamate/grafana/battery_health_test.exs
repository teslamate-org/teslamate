defmodule TeslaMate.Grafana.BatteryHealthTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log

  @dashboard_path Path.expand("../../../../grafana/dashboards/battery-health.json", __DIR__)

  test "a change in rated efficiency preserves estimated capacity while a capacity loss remains visible" do
    car = create_car()

    # Separate months keep the daily and half-month series independently testable.
    record_charge(car, ~U[2024-01-01 00:00:00Z], 100, 90, 200)
    record_charge(car, ~U[2024-02-01 00:00:00Z], 200, 90, 200)
    record_charge(car, ~U[2024-03-01 00:00:00Z], 300, 90, 160)
    record_charge(car, ~U[2024-04-01 00:00:00Z], 400, 80, 200)

    {dashboard, json, capacities} = summary(car)
    assert_in_delta capacities["UsableNew"], 90, 0.01
    assert_in_delta capacities["CurrentCapacity"], 87.5, 0.01

    history = Enum.find(dashboard["panels"], &(&1["title"] == "Battery Capacity by Mileage"))
    assert length(history["targets"]) == 2

    for target <- history["targets"] do
      sql = ~s|SELECT "kWh"::float FROM (#{target["rawSql"]}) AS history ORDER BY "Odometer"|
      assert run_query(sql, car.id, json).rows == [[90.0], [90.0], [90.0], [80.0]]
    end
  end

  test "range gained while the energy counter is zero does not lower capacity across a wheel change" do
    car = create_car()

    for {date, odometer, wh_per_km} <- [
          {~U[2024-01-01 00:00:00Z], 100, 200},
          {~U[2024-02-01 00:00:00Z], 200, 160}
        ] do
      samples =
        for {soc, added} <- [{30, 0}, {40, 0}, {42, 2}, {80, 40}] do
          sample(soc, added, 100 * 1000 / wh_per_km * soc / 100)
        end

      record_samples(car, date, odometer, samples)
    end

    {dashboard, json, capacities} = summary(car)
    assert_in_delta capacities["UsableNew"], 100, 0.01
    assert_in_delta capacities["CurrentCapacity"], 100, 0.01

    history = Enum.find(dashboard["panels"], &(&1["title"] == "Battery Capacity by Mileage"))

    for target <- history["targets"] do
      sql = ~s|SELECT "kWh"::float FROM (#{target["rawSql"]}) AS history ORDER BY "Odometer"|
      assert run_query(sql, car.id, json).rows == [[100.0], [100.0]]
    end
  end

  test "a logger starting mid-charge subtracts the initial positive energy counter" do
    car = create_car()

    process =
      record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
        sample(30, 4, 150),
        sample(80, 54, 400)
      ])

    assert session_capacities(car) == [[process.id, 100.0]]
  end

  test "the 100 km threshold applies to the measured positive-energy interval" do
    car = create_car()

    record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
      sample(10, 0, 50),
      sample(20, 1, 100),
      sample(40, 21, 199.99)
    ])

    at_boundary =
      record_samples(car, ~U[2024-01-02 00:00:00Z], 200, [
        sample(10, 0, 50),
        sample(20, 1, 100),
        sample(40, 21, 200)
      ])

    assert session_capacities(car) == [[at_boundary.id, 100.0]]
  end

  test "one positive-energy sample is not enough even if total session range exceeds 100 km" do
    car = create_car()

    record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
      sample(30, 0, 150),
      sample(80, 50, 400)
    ])

    assert session_capacities(car) == []
  end

  test "a zero reset limits the measurement to the final positive-energy interval" do
    car = create_car()

    process =
      record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
        sample(50, 30, 250),
        sample(52, 0, 260),
        sample(53, 1, 265),
        sample(83, 31, 415)
      ])

    assert session_capacities(car) == [[process.id, 100.0]]
  end

  test "a small return to zero uses the same reset rule" do
    car = create_car()

    process =
      record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
        sample(20, 0.01, 100),
        sample(20, 0, 100.02),
        sample(21, 1, 105),
        sample(61, 41, 305)
      ])

    assert session_capacities(car) == [[process.id, 100.0]]
  end

  test "trailing zero counters and invalid readings do not mix the final energy, range and SOC" do
    car = create_car()

    process =
      record_samples(car, ~U[2024-01-01 00:00:00Z], 100, [
        sample(20, 1, 100),
        sample(80, 61, 400),
        sample(90, 0, 450),
        sample(0, 65, 425),
        sample(90, 66, 0)
      ])

    assert session_capacities(car) == [[process.id, 100.0]]
  end

  test "incomplete sessions and sessions from another car are excluded" do
    car = create_car()
    other_car = create_car(78)

    record_samples(
      car,
      ~U[2024-01-01 00:00:00Z],
      100,
      [sample(20, 1, 100), sample(80, 61, 400)],
      complete?: false
    )

    record_charge(other_car, ~U[2024-01-01 00:00:00Z], 100, 90, 200)
    assert session_capacities(car) == []
  end

  test "a new car can use fewer than ten qualifying charges" do
    for count <- 1..9 do
      car = create_car(100 + count)

      for i <- 0..(count - 1) do
        date = DateTime.add(~U[2024-01-01 00:00:00Z], i * 86_400)
        record_charge(car, date, i * 100, 94 - i, 200)
      end

      {_, _, capacities} = summary(car)
      assert length(session_capacities(car)) == count
      assert_in_delta capacities["UsableNew"], 94, 0.01
      assert_in_delta capacities["CurrentCapacity"], 94 - (count - 1) / 2, 0.01
    end
  end

  test "a car without qualifying history preserves the existing no-data result" do
    car = create_car()
    {_, _, capacities} = summary(car)
    assert session_capacities(car) == []
    assert capacities["UsableNew"] == nil
    assert capacities["CurrentCapacity"] == 1
  end

  defp create_car(id \\ 77) do
    {:ok, car} = Log.create_car(%{eid: id, vid: id, vin: "battery-health-test-#{id}"})
    car
  end

  defp record_charge(car, date, odometer, capacity_kwh, wh_per_km) do
    samples =
      for {soc, added} <- [{30, 0}, {40, capacity_kwh / 10}, {80, capacity_kwh / 2}] do
        sample(soc, added, capacity_kwh * 1000 / wh_per_km * soc / 100)
      end

    record_samples(car, date, odometer, samples)
  end

  defp sample(soc, added, range) do
    %{
      ideal_battery_range_km: range,
      rated_battery_range_km: range,
      battery_level: soc,
      usable_battery_level: soc,
      charge_energy_added: added,
      charger_power: 50
    }
  end

  defp record_samples(car, date, odometer, samples, opts \\ []) do
    position = %{date: date, latitude: 0.0, longitude: 0.0, odometer: odometer}
    {:ok, process} = Log.start_charging_process(car, position)

    for {attrs, index} <- Enum.with_index(samples) do
      attrs = Map.put(attrs, :date, DateTime.add(date, index * 60))
      {:ok, _} = Log.insert_charge(process, attrs)
    end

    if Keyword.get(opts, :complete?, true) do
      {:ok, process} = Log.complete_charging_process(process)
      process
    else
      process
    end
  end

  defp summary(car) do
    dashboard = @dashboard_path |> File.read!() |> Jason.decode!()
    aux = Enum.find(dashboard["templating"]["list"], &(&1["name"] == "aux"))
    assert aux["definition"] == aux["query"]
    %{rows: [[json]]} = run_query(aux["query"], car.id)
    {dashboard, json, Jason.decode!(json)}
  end

  defp session_capacities(car) do
    dashboard = @dashboard_path |> File.read!() |> Jason.decode!()
    aux = Enum.find(dashboard["templating"]["list"], &(&1["name"] == "aux"))
    [_, tail] = String.split(aux["query"], "SessionCapacity AS (", parts: 2)
    [cte, _] = String.split(tail, "),\n\nCurrentCapacity AS (", parts: 2)

    sql =
      "WITH SessionCapacity AS (#{cte}) SELECT id, capacity::float FROM SessionCapacity ORDER BY id"

    run_query(sql, car.id).rows
  end

  defp run_query(sql, car_id, aux \\ "") do
    sql
    |> String.replace("$car_id", Integer.to_string(car_id))
    |> String.replace("${preferred_range}", "rated")
    |> String.replace("$length_unit", "km")
    |> String.replace("$__timezone", "UTC")
    |> String.replace("${custom_kwh_new:sqlstring}", "'0'")
    |> String.replace("${custom_max_range:sqlstring}", "'0'")
    |> String.replace("$aux", aux)
    |> Repo.query!()
  end
end
