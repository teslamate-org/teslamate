defmodule TeslaMateWeb.LayoutView do
  use TeslaMateWeb, :view

  @dashboards_path "./grafana/dashboards"
  @dashboards File.ls!(@dashboards_path)
              |> Enum.filter(&(Path.extname(&1) == ".json"))
              |> Enum.map(&Path.join([@dashboards_path, &1]))
              |> Enum.map(&File.read!/1)
              |> Enum.map(&Jason.decode!/1)
              |> Enum.map(&Map.take(&1, ["title", "uid"]))
              |> Enum.sort_by(& &1["title"])

  defp dashboards, do: @dashboards
end
