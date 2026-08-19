defmodule TeslaMate.Grafana.DashboardQueriesTest do
  use ExUnit.Case, async: true

  @dashboard_directory Path.expand("../../../grafana/dashboards", __DIR__)
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

  # Grafana geofence variable: `geofence_id in ($geofence)` fails when $geofence is empty (All).
  # Postgres parses `in ()` as syntax error even though `OR '${geofence:pipe}' = '-1'` is true.
  # Safe form uses ANY(string_to_array('${geofence:pipe}', '|' )::int[]) and handles '' and '-1'.
  @unsafe_geofence_in ~r/geofence[_.]id\s+in\s*\(\$geofence\)/
  @safe_geofence_any ~r/=\s*ANY\(string_to_array\('\$\{geofence:pipe\}'/
  @empty_geofence_handling ~r/'\$\{geofence:pipe\}' = ''/

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

  test "geofence filters use safe ANY handling for All/empty" do
    queries = dashboard_directory_queries()

    offenders =
      queries
      |> Enum.filter(fn {_path, query} -> query =~ @unsafe_geofence_in end)
      |> Enum.map(fn {path, _query} -> path end)

    assert offenders == [],
           "unsafe geofence_id in ($geofence) found in #{inspect(offenders)} - use ANY(string_to_array('${geofence:pipe}', '|' )::int[])"

    safe_queries =
      queries
      |> Enum.filter(fn {_path, query} -> query =~ @safe_geofence_any end)

    assert safe_queries != [],
           "no safe geofence ANY(string_to_array) pattern found - expected at least charges.json, drives.json, charging-stats.json"

    missing_empty_handling =
      safe_queries
      |> Enum.reject(fn {_path, query} -> query =~ @empty_geofence_handling end)
      |> Enum.map(fn {path, _query} -> path end)

    assert missing_empty_handling == [],
           "safe geofence filters should handle empty string '' for All (Grafana 12 vs 13): #{inspect(missing_empty_handling)}"
  end

  test "detector flags unsafe geofence in () pattern" do
    unsafe = "'${geofence:pipe}' = '-1' OR geofence_id in ($geofence)"
    assert unsafe =~ @unsafe_geofence_in
    refute unsafe =~ @safe_geofence_any

    safe =
      "'${geofence:pipe}' = '' OR '${geofence:pipe}' = '-1' OR geofence_id = ANY(string_to_array('${geofence:pipe}' , '|' )::int[])"

    refute safe =~ @unsafe_geofence_in
    assert safe =~ @safe_geofence_any
    assert safe =~ @empty_geofence_handling
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
