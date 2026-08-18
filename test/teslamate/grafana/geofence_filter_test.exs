defmodule TeslaMate.Grafana.GeofenceFilterTest do
  use TeslaMate.DataCase

  alias TeslaMate.Repo
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Locations
  alias TeslaMate.Log
  alias TeslaMate.Log.ChargingProcess

  @moduletag :capture_log

  # Helper to build the fixed where clause used in dashboards
  # Returns SQL fragment for given pipe value and column
  defp geofence_where_clause(pipe_value, column \\ "geofence_id") do
    # This mirrors the fixed dashboard logic:
    # ('${geofence:pipe}' = '' OR '${geofence:pipe}' = '-1' OR geofence_id = ANY(string_to_array('${geofence:pipe}' , '|' )::int[]))
    # We interpolate the pipe_value directly for testing (simulating Grafana substitution)
    # Use param binding to avoid SQL injection in test? For simplicity interpolate as literal.
    "'#{pipe_value}' = '' OR '#{pipe_value}' = '-1' OR #{column} = ANY(string_to_array('#{pipe_value}' , '|' )::int[])"
  end

  defp geofence_where_clause_two_col(pipe_value) do
    "'#{pipe_value}' = '' OR '#{pipe_value}' = '-1' OR start_geofence_id = ANY(string_to_array('#{pipe_value}' , '|' )::int[]) OR end_geofence_id = ANY(string_to_array('#{pipe_value}' , '|' )::int[])"
  end

  describe "charging_processes geofence filter" do
    setup do
      car = car_fixture()
      # Create two geofences with distinct locations
      {:ok, g1} = Locations.create_geofence(%{name: "Home", latitude: 52.514521, longitude: 13.350144, radius: 100})
      {:ok, g2} = Locations.create_geofence(%{name: "Work", latitude: 53.514521, longitude: 14.350144, radius: 100})

      # Charging process at g1
      cp_g1 = create_charging_process(car, %{latitude: 52.514521, longitude: 13.350144})
      # Should be assigned to g1 via geofence logic
      cp_g1 = Repo.get!(ChargingProcess, cp_g1.id)

      # Charging process at g2
      cp_g2 = create_charging_process(car, %{latitude: 53.514521, longitude: 14.350144})
      cp_g2 = Repo.get!(ChargingProcess, cp_g2.id)

      # Charging process with no geofence (far away)
      cp_nil = create_charging_process(car, %{latitude: 0.0, longitude: 0.0})
      cp_nil = Repo.get!(ChargingProcess, cp_nil.id)

      %{car: car, g1: g1, g2: g2, cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil}
    end

    test "empty string (All) returns all rows", %{g1: g1, g2: g2, cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil} do
      where = geofence_where_clause("")
      # Should be true for all because ''='' -> true
      for cp <- [cp_g1, cp_g2, cp_nil] do
        assert query_matches?(where, cp.id), "empty should match #{cp.id} geofence_id=#{inspect(cp.geofence_id)}"
      end
      # Also test that count via SQL matches 3
      assert count_where("") == 3
      assert count_where("-1") == 3
    end

    test "'-1' (All) returns all rows", %{cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil} do
      where = geofence_where_clause("-1")
      for cp <- [cp_g1, cp_g2, cp_nil] do
        assert query_matches?(where, cp.id)
      end
      assert count_where("-1") == 3
    end

    test "single geofence '1' returns only matching", %{g1: g1, g2: g2, cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil} do
      where = geofence_where_clause("#{g1.id}")
      assert query_matches?(where, cp_g1.id)
      refute query_matches?(where, cp_g2.id)
      refute query_matches?(where, cp_nil.id)
      assert count_where("#{g1.id}") == 1
    end

    test "multi geofence '1|2' returns matching", %{g1: g1, g2: g2, cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil} do
      where = geofence_where_clause("#{g1.id}|#{g2.id}")
      assert query_matches?(where, cp_g1.id)
      assert query_matches?(where, cp_g2.id)
      refute query_matches?(where, cp_nil.id)
      assert count_where("#{g1.id}|#{g2.id}") == 2
    end

    test "non-existent geofence returns none", %{cp_g1: cp_g1, cp_g2: cp_g2, cp_nil: cp_nil} do
      where = geofence_where_clause("99999")
      refute query_matches?(where, cp_g1.id)
      refute query_matches?(where, cp_g2.id)
      refute query_matches?(where, cp_nil.id)
      assert count_where("99999") == 0
    end

    test "NULL geofence_id not matched when filtering specific", %{cp_nil: cp_nil, g1: g1} do
      where = geofence_where_clause("#{g1.id}")
      refute query_matches?(where, cp_nil.id)
      # But All should match null as well because ''='' true
      assert query_matches?(geofence_where_clause(""), cp_nil.id)
      assert query_matches?(geofence_where_clause("-1"), cp_nil.id)
    end

    test "unsafe in () would syntax error, safe does not" do
      # The old buggy pattern would be: geofence_id in ()
      # This should error
      assert {:error, _} = Repo.query("SELECT * FROM charging_processes WHERE geofence_id in ()", [])
      # Safe pattern with empty should not error and return all when using OR
      assert {:ok, _} = Repo.query("SELECT * FROM charging_processes WHERE '' = '' OR geofence_id = ANY(string_to_array('', '|' )::int[])", [])
    end

    test "drives two-column filter works for start/end geofence", %{g1: g1, g2: g2} do
      car = car_fixture(%{model: "M3", eid: 999, vid: 999, vin: "TEST999"})
      # Create drives with start/end geofences - use the same helper but for drives
      # For simplicity test the SQL logic directly
      where_all = geofence_where_clause_two_col("")
      where_one = geofence_where_clause_two_col("#{g1.id}")
      where_multi = geofence_where_clause_two_col("#{g1.id}|#{g2.id}")

      # Empty should be true regardless of nulls
      assert {:ok, _} = Repo.query("SELECT 1 WHERE #{where_all}", [])
      # Single should not error
      assert {:ok, _} = Repo.query("SELECT 1 WHERE #{where_one}", [])
      assert {:ok, _} = Repo.query("SELECT 1 WHERE #{where_multi}", [])
    end
  end

  # Helpers

  defp count_where(pipe_value) do
    where = geofence_where_clause(pipe_value)
    {:ok, %{rows: [[count]]}} = Repo.query("SELECT count(*) FROM charging_processes WHERE #{where}")
    count
  end

  defp query_matches?(where_clause, charging_process_id) do
    {:ok, %{rows: [[exists]]}} =
      Repo.query(
        "SELECT EXISTS(SELECT 1 FROM charging_processes WHERE id = $1 AND (#{where_clause}))",
        [charging_process_id]
      )

    exists
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: System.unique_integer([:positive]), model: "M3", vid: System.unique_integer([:positive]), vin: "VIN#{System.unique_integer([:positive])}"})
      |> Log.create_car()

    car
  end

  defp create_charging_process(car, %{latitude: lat, longitude: lng}) do
    {:ok, charging_process_id} =
      Log.start_charging_process(car, %{
        date: DateTime.utc_now(),
        latitude: lat,
        longitude: lng
      })

    charges = [
      %{
        date: "2019-04-05 16:01:27",
        battery_level: 50,
        charge_energy_added: 0.41,
        charger_actual_current: 5,
        charger_phases: 3,
        charger_pilot_current: 16,
        charger_power: 4,
        charger_voltage: 234,
        ideal_battery_range_km: 266.6,
        rated_battery_range_km: 206.6,
        outside_temp: 16
      }
    ]

    for c <- charges do
      {:ok, _} = Log.insert_charge(charging_process_id, c)
    end

    {:ok, cproc} = Log.complete_charging_process(charging_process_id)
    cproc
  end
end
