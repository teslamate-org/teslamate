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
