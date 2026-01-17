defmodule TeslaMateWeb.LayoutView do
  use TeslaMateWeb, :view

  import Phoenix.Component
  use PhoenixHTMLHelpers

  dashboards_en =
    for dashboard_path <- Path.wildcard("grafana/dashboards/*.json") do
      @external_resource Path.relative_to_cwd(dashboard_path)

      dashboard_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.take(["title", "uid"])
    end

  dashboards_fr =
    for dashboard_path <- Path.wildcard("grafana/dashboards/fr/*.json") do
      @external_resource Path.relative_to_cwd(dashboard_path)

      dashboard_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.take(["title", "uid"])
    end

  @dashboards_en Enum.sort_by(dashboards_en, & &1["title"])
  @dashboards_fr Enum.sort_by(dashboards_fr, & &1["title"])

  defp list_dashboards do
    locale = Gettext.get_locale(TeslaMateWeb.Gettext) || ""

    if String.starts_with?(locale, "fr") and @dashboards_fr != [] do
      @dashboards_fr
    else
      @dashboards_en
    end
  end
end
