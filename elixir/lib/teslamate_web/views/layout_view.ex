defmodule TeslaMateWeb.LayoutView do
  use TeslaMateWeb, :view

  import Phoenix.Component
  use PhoenixHTMLHelpers

  @dashboards_dir Path.expand("../../../../grafana/dashboards", __DIR__)

  dashboards =
    for dashboard_path <- Path.wildcard(Path.join(@dashboards_dir, "*.json")) do
      @external_resource Path.relative_to_cwd(dashboard_path)

      dashboard_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.take(["title", "uid"])
    end

  @dashboards Enum.sort_by(dashboards, & &1["title"])
  defp list_dashboards, do: @dashboards
end
