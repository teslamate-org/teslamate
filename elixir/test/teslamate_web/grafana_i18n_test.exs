defmodule TeslaMateWeb.GrafanaI18nTest do
  use ExUnit.Case, async: true

  @dashboards_dir Path.expand("../../../grafana/dashboards", __DIR__)
  @pack_path Path.expand("../../../grafana/i18n/it.json", __DIR__)
  @localizable_keys ~w(title description label displayName legendFormat tooltip noValue text alias)
  @sql_alias ~r/\bAS\s+["']([^"']+)["']/i

  test "Italian Grafana locale pack covers every user-visible dashboard string" do
    pack = @pack_path |> File.read!() |> Jason.decode!()
    translated = pack |> Map.fetch!("strings") |> Map.keys() |> MapSet.new()
    passthrough = pack |> Map.get("passthrough", []) |> MapSet.new()
    dashboard_titles = Map.fetch!(pack, "dashboard_titles")

    {candidates, missing_dashboard_titles} =
      @dashboards_dir
      |> Path.join("**/*.json")
      |> Path.wildcard()
      |> Enum.reduce({MapSet.new(), []}, fn path, {acc, missing_titles} ->
        dashboard = path |> File.read!() |> Jason.decode!()

        relative_key =
          path
          |> Path.relative_to(@dashboards_dir)
          |> Path.rootname()
          |> String.replace("\\", "/")

        missing_titles =
          if Map.has_key?(dashboard_titles, relative_key) do
            missing_titles
          else
            [relative_key | missing_titles]
          end

        candidates =
          dashboard
          |> collect_visible_strings()
          |> maybe_delete(dashboard["title"])
          |> MapSet.union(acc)

        {candidates, missing_titles}
      end)

    missing =
      candidates
      |> MapSet.difference(translated)
      |> MapSet.difference(passthrough)
      |> Enum.sort()

    assert missing_dashboard_titles == [],
           "Missing translated dashboard titles: #{inspect(Enum.sort(missing_dashboard_titles))}"

    assert missing == [],
           "Missing Italian Grafana dashboard strings:\n" <>
             Enum.map_join(missing, "\n", &"  - #{inspect(&1)}")
  end

  defp maybe_delete(set, nil), do: set
  defp maybe_delete(set, title), do: MapSet.delete(set, title)

  defp collect_visible_strings(value), do: collect_visible_strings(value, MapSet.new())

  defp collect_visible_strings(value, acc) when is_list(value) do
    Enum.reduce(value, acc, &collect_visible_strings/2)
  end

  defp collect_visible_strings(value, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {key, item}, acc ->
      cond do
        key in @localizable_keys and is_binary(item) ->
          add_visible(item, acc)

        key == "renameByName" and is_map(item) ->
          Enum.reduce(Map.values(item), acc, &add_visible/2)

        key == "aliasColors" and is_map(item) ->
          Enum.reduce(Map.keys(item), acc, &add_visible/2)

        key == "value" and value["id"] == "displayName" and is_binary(item) ->
          add_visible(item, acc)

        key == "rawSql" and is_binary(item) ->
          @sql_alias
          |> Regex.scan(item, capture: :all_but_first)
          |> Enum.reduce(acc, fn [alias_name], acc -> add_visible(alias_name, acc) end)

        true ->
          collect_visible_strings(item, acc)
      end
    end)
  end

  defp collect_visible_strings(_value, acc), do: acc

  defp add_visible(value, acc) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        acc

      # Grafana variables, field references, numeric values and time intervals
      # are identifiers/data, not natural-language text to translate.
      Regex.match?(~r/^\\$\\{?[A-Za-z_][A-Za-z_0-9.:\\[\\]]*\\}?$/, value) ->
        acc

      Regex.match?(~r/^[0-9]+(?:\\.[0-9]+)?(?:ms|s|m|h|d|w)?$/, value) ->
        acc

      value in ["--", ".", "ID"] ->
        acc

      true ->
        MapSet.put(acc, value)
    end
  end

  defp add_visible(_value, acc), do: acc
end
