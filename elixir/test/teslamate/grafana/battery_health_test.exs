defmodule TeslaMate.Grafana.BatteryHealthTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log

  @dashboard_path Path.expand("../../../../grafana/dashboards/battery-health.json", __DIR__)

  test "a change in rated efficiency preserves estimated capacity while a capacity loss remains visible" do
    {:ok, car} = Log.create_car(%{eid: 77, vid: 77, vin: "battery-health-test"})

    # Separate months keep the daily and half-month series independently testable.
    record_charge(car, ~U[2024-01-01 00:00:00Z], 100, 90, 200)
    record_charge(car, ~U[2024-02-01 00:00:00Z], 200, 90, 200)
    record_charge(car, ~U[2024-03-01 00:00:00Z], 300, 90, 160)
    record_charge(car, ~U[2024-04-01 00:00:00Z], 400, 80, 200)

    dashboard = @dashboard_path |> File.read!() |> Jason.decode!()
    aux = Enum.find(dashboard["templating"]["list"], &(&1["name"] == "aux"))
    assert aux["definition"] == aux["query"]
    %{rows: [[json]]} = run_query(aux["query"], car.id)
    capacities = Jason.decode!(json)
    assert_in_delta capacities["UsableNew"], 90, 0.01
    assert_in_delta capacities["CurrentCapacity"], 87.5, 0.01

    history = Enum.find(dashboard["panels"], &(&1["title"] == "Battery Capacity by Mileage"))
    assert length(history["targets"]) == 2

    for target <- history["targets"] do
      sql = ~s|SELECT "kWh"::float FROM (#{target["rawSql"]}) AS history ORDER BY "Odometer"|
      assert run_query(sql, car.id, json).rows == [[90.0], [90.0], [90.0], [80.0]]
    end
  end

  defp record_charge(car, date, odometer, capacity_kwh, wh_per_km) do
    position = %{date: date, latitude: 0.0, longitude: 0.0, odometer: odometer}
    {:ok, process} = Log.start_charging_process(car, position)

    for {soc, time, added} <- [{30, date, 0}, {80, DateTime.add(date, 3600), capacity_kwh / 2}] do
      range = capacity_kwh * 1000 / wh_per_km * soc / 100

      {:ok, _} =
        Log.insert_charge(process, %{
          date: time,
          ideal_battery_range_km: range,
          rated_battery_range_km: range,
          battery_level: soc,
          usable_battery_level: soc,
          charge_energy_added: added,
          charger_power: 50
        })
    end

    {:ok, _} = Log.complete_charging_process(process)
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
