defmodule TeslaMate.Grafana.DashboardQueriesTest do
  use ExUnit.Case, async: true

  @dashboard_directory Path.expand("../../../grafana/dashboards", __DIR__)
  @query_keys ~w(definition query rawSql)

  # A latest-position lookup needs the partial-index predicate introduced in
  # #5438. Match each positions block independently so a filter in another CTE
  # cannot hide an unindexed lookup.
  @latest_position_block ~r/from positions\b(?:(?!\bfrom\b).)*?order by date desc(?:(?!\bfrom\b).)*?limit 1\b/

  test "latest position queries use complete position rows" do
    dashboards = Path.wildcard(Path.join(@dashboard_directory, "**/*.json"))

    assert dashboards != []

    offenders =
      dashboards
      |> Enum.flat_map(&dashboard_queries/1)
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

  defp unfiltered_latest_position_blocks(query) do
    normalized =
      query
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.replace(~r/\bextract\s*\(\s*epoch\s+from\b/, "extract(epoch_from")

    @latest_position_block
    |> Regex.scan(normalized)
    |> List.flatten()
    |> Enum.reject(&String.contains?(&1, "ideal_battery_range_km is not null"))
  end
end
