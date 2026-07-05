defmodule TeslaMate.Grafana.DashboardQueriesTest do
  use ExUnit.Case, async: true

  @query_keys ~w(definition query rawSql)

  # A "latest position" lookup is a `FROM positions ... ORDER BY date DESC LIMIT 1`
  # block. After the btree index on positions(date) was replaced with BRIN, such a
  # block only stays fast if it also filters `ideal_battery_range_km IS NOT NULL`,
  # which lets it use the partial index `positions(car_id, date) WHERE
  # ideal_battery_range_km IS NOT NULL`. A query can contain several sub-blocks
  # (e.g. a UNION of positions and charges), so we match each positions block on
  # its own rather than searching the whole query string. See issue #5306.
  #
  # `(?:(?!\bfrom\b).)*?` keeps a match from spilling across into a following
  # `FROM charges`/CTE, so the filter must appear inside the *same* positions block.
  @latest_position_block ~r/from positions\b(?:(?!\bfrom\b).)*?order by date desc(?:(?!\bfrom\b).)*?limit 1/

  test "latest position queries use complete position rows" do
    offenders =
      "grafana/dashboards/**/*.json"
      |> Path.wildcard()
      |> Enum.flat_map(&dashboard_queries/1)
      |> Enum.flat_map(fn {path, query} ->
        query
        |> unfiltered_latest_position_blocks()
        |> Enum.map(&"#{path}: #{&1}")
      end)

    assert offenders == []
  end

  test "detector flags a positions block missing the filter even when the token appears elsewhere" do
    # Negative control: an unrelated CTE mentions the filter token, but the actual
    # positions latest-block does not. A whole-string check would wrongly pass this.
    query = """
    WITH t AS (SELECT 1 WHERE ideal_battery_range_km IS NOT NULL)
    SELECT date FROM positions WHERE car_id = 1 ORDER BY date DESC LIMIT 1
    """

    assert unfiltered_latest_position_blocks(query) != []
  end

  test "detector accepts a positions block that carries the filter" do
    query =
      "SELECT date FROM positions WHERE car_id = 1 AND ideal_battery_range_km IS NOT NULL " <>
        "ORDER BY date DESC LIMIT 1"

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

    @latest_position_block
    |> Regex.scan(normalized)
    |> List.flatten()
    |> Enum.reject(&String.contains?(&1, "ideal_battery_range_km is not null"))
  end
end
