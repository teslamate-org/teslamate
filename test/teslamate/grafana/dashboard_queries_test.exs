defmodule TeslaMate.Grafana.DashboardQueriesTest do
  use ExUnit.Case, async: true

  @dashboard_directory Path.expand("../../../grafana/dashboards", __DIR__)
  @location_privacy_marker "-- hide location details inside selected geo-fences"
  @location_privacy_paths %{
    "internal/drive-details.json" => 1,
    "locations.json" => 1,
    "trip.json" => 1,
    "visited.json" => 1
  }
  @query_keys ~w(definition query rawSql)

  # A latest-position lookup needs the partial-index predicate introduced in
  # #5438. Match each positions block independently so a filter in another CTE
  # cannot hide an unindexed lookup.
  @latest_position_block ~r/from positions\b(?:(?!\bfrom\b).)*?order by date desc(?:(?!\bfrom\b).)*?limit 1\b/

  # The energy integration falls back to charger_power when phase detection
  # fails (#5558). Power expressions built on the determine_phases variable
  # replicate that integration and must carry the same fallback.
  @phases_power_without_fallback ~r/(?<!coalesce\()cast\(nullif\(\$\{determine_phases:sqlstring\}, ''\) as numeric\) \* charger_actual_current/

  # charger_actual_current and charger_voltage are smallint columns and
  # Postgres multiplies two smallints into a smallint — battery-side DC
  # readings (e.g. 155 A x 230 V) overflow the product. A chain that already
  # starts with a wider type is safe.
  @uncast_smallint_product ~r/(?<!\* )(?:\w+\.)?charger_actual_current \* (?:\w+\.)?charger_voltage/

  test "location privacy filter is limited to four detail queries" do
    matches =
      dashboard_directory_queries()
      |> Enum.filter(fn {_path, query} ->
        String.contains?(normalize(query), @location_privacy_marker)
      end)

    frequencies =
      matches
      |> Enum.map(fn {path, _query} -> Path.relative_to(path, @dashboard_directory) end)
      |> Enum.frequencies()

    assert frequencies == @location_privacy_paths

    for {path, query} <- matches do
      query = normalize(query)
      relative_path = Path.relative_to(path, @dashboard_directory)

      assert query =~ "not exists ("

      if relative_path == "trip.json" do
        assert count(query, "hidden_centers as materialized") == 1
        assert count(query, "hidden_geofences as materialized") == 1
        assert count(query, "from geofences") == 1
        assert count(query, "where g.hide_details") == 1
        assert count(query, "ll_to_earth(g.latitude, g.longitude)") == 1
        assert count(query, "earth_box(center, radius)") == 1
        assert query =~ "from hidden_geofences h"
        assert query =~ "where h.bounds @> ll_to_earth(p.latitude, p.longitude)"

        assert query =~
                 "earth_distance( h.center, ll_to_earth(p.latitude, p.longitude) ) < h.radius"

        assert query =~ "where p.car_id = $car_id and $__timefilter(d.start_date)"

        assert query =~
                 "where p.car_id = $car_id and drive_id is null and $__timefilter(date)"

        refute query =~ "position_earth as materialized"
      else
        assert query =~ "from geofences g"
        assert query =~ "where g.hide_details"
        assert query =~ "earth_box("
        assert query =~ "earth_distance("
        assert query =~ ") < g.radius"
      end
    end
  end

  test "latest position queries use complete position rows" do
    queries = dashboard_directory_queries()

    assert queries != []

    offenders =
      queries
      |> Enum.flat_map(fn {path, query} ->
        query
        |> unfiltered_latest_position_blocks()
        |> Enum.map(&"#{path}: #{&1}")
      end)

    assert offenders == []
  end

  test "detector flags a positions block missing the filter even when it appears elsewhere" do
    query = """
    WITH metadata AS (SELECT 1 WHERE ideal_battery_range_km IS NOT NULL)
    SELECT date FROM positions WHERE car_id = 1 ORDER BY date DESC LIMIT 1
    """

    assert unfiltered_latest_position_blocks(query) != []
  end

  test "detector accepts a positions block with the filter" do
    query =
      "SELECT date FROM positions WHERE car_id = 1 AND ideal_battery_range_km IS NOT NULL " <>
        "ORDER BY date DESC LIMIT 1"

    assert unfiltered_latest_position_blocks(query) == []
  end

  test "detector handles EXTRACT expressions in a positions block" do
    query = """
    SELECT EXTRACT(EPOCH FROM date)
    FROM positions
    WHERE car_id = 1
    ORDER BY date DESC
    LIMIT 1
    """

    assert unfiltered_latest_position_blocks(query) != []
  end

  test "detector ignores positions queries with a larger limit" do
    query = "SELECT date FROM positions WHERE car_id = 1 ORDER BY date DESC LIMIT 10"

    assert unfiltered_latest_position_blocks(query) == []
  end

  test "phases-based power expressions fall back to charger_power" do
    offenders =
      dashboard_directory_queries()
      |> Enum.filter(fn {_path, query} -> normalize(query) =~ @phases_power_without_fallback end)
      |> Enum.map(fn {path, _query} -> path end)

    assert offenders == []
  end

  test "detector flags a phases power expression without the fallback" do
    unfixed =
      "avg(case when charger_phases >= 1 then " <>
        "cast(nullif(${determine_phases:sqlstring}, '') as numeric) * charger_actual_current" <>
        " * charger_voltage / 1000.0 else charger_power end)"

    assert normalize(unfixed) =~ @phases_power_without_fallback

    fixed =
      "avg(case when charger_phases >= 1 then " <>
        "coalesce(cast(nullif(${determine_phases:sqlstring}, '') as numeric) * charger_actual_current" <>
        " * charger_voltage / 1000.0, charger_power) else charger_power end)"

    refute normalize(fixed) =~ @phases_power_without_fallback
  end

  test "phase detection queries never yield a phase count of zero" do
    tolerance_queries =
      dashboard_directory_queries()
      |> Enum.map(fn {path, query} -> {path, normalize(query)} end)
      |> Enum.filter(fn {_path, query} -> String.contains?(query, "abs(round(p) - p) <= 0.3") end)

    assert tolerance_queries != []

    offenders =
      tolerance_queries
      |> Enum.reject(fn {_path, query} ->
        String.contains?(query, "round(p) > 0 and abs(round(p) - p) <= 0.3")
      end)
      |> Enum.map(fn {path, _query} -> path end)

    assert offenders == []
  end

  test "smallint products in queries are cast before multiplying" do
    offenders =
      dashboard_directory_queries()
      |> Enum.filter(fn {_path, query} -> normalize(query) =~ @uncast_smallint_product end)
      |> Enum.map(fn {path, _query} -> path end)

    assert offenders == []
  end

  test "detector flags an uncast smallint product" do
    uncast = "nullif(c.charger_actual_current * c.charger_voltage, 0)"
    assert normalize(uncast) =~ @uncast_smallint_product

    cast = "nullif(c.charger_actual_current::int * c.charger_voltage, 0)"
    refute normalize(cast) =~ @uncast_smallint_product

    numeric_chain = "cast(x as numeric) * charger_actual_current * charger_voltage / 1000.0"
    refute normalize(numeric_chain) =~ @uncast_smallint_product
  end

  defp dashboard_directory_queries do
    @dashboard_directory
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.flat_map(&dashboard_queries/1)
  end

  defp dashboard_queries(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> collect_queries()
    |> Enum.map(&{path, &1})
  end

  defp collect_queries(%{} = value) do
    own_queries =
      value
      |> Map.take(@query_keys)
      |> Map.values()
      |> Enum.filter(&is_binary/1)

    child_queries =
      value
      |> Map.values()
      |> Enum.flat_map(&collect_queries/1)

    own_queries ++ child_queries
  end

  defp collect_queries(values) when is_list(values), do: Enum.flat_map(values, &collect_queries/1)
  defp collect_queries(_value), do: []

  defp count(query, pattern) do
    query
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp normalize(query) do
    query
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end

  defp unfiltered_latest_position_blocks(query) do
    normalized =
      query
      |> normalize()
      |> String.replace(~r/\bextract\s*\(\s*epoch\s+from\b/, "extract(epoch_from")

    @latest_position_block
    |> Regex.scan(normalized)
    |> List.flatten()
    |> Enum.reject(&String.contains?(&1, "ideal_battery_range_km is not null"))
  end
end
