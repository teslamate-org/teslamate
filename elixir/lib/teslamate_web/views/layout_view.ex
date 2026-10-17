defmodule TeslaMateWeb.LayoutView do
  use TeslaMateWeb, :view

  import Phoenix.Component
  use PhoenixHTMLHelpers

  @dashboards_dir Path.expand("../../../../grafana/dashboards", __DIR__)
  @dashboard_i18n_dir Path.expand("../../../../grafana/i18n", __DIR__)

  dashboards =
    for dashboard_path <- Path.wildcard(Path.join(@dashboards_dir, "*.json")) do
      @external_resource Path.relative_to_cwd(dashboard_path)

      dashboard =
        dashboard_path
        |> File.read!()
        |> Jason.decode!()
        |> Map.take(["title", "uid"])

      Map.put(dashboard, "slug", Path.basename(dashboard_path, ".json"))
    end

  locale_packs =
    for pack_path <- Path.wildcard(Path.join(@dashboard_i18n_dir, "*.json")), into: %{} do
      @external_resource Path.relative_to_cwd(pack_path)

      pack =
        pack_path
        |> File.read!()
        |> Jason.decode!()

      {pack["locale"], pack["dashboard_titles"] || %{}}
    end

  @dashboards dashboards
  @dashboard_locale_packs locale_packs

  defp list_dashboards do
    TeslaMateWeb.Gettext
    |> Gettext.get_locale()
    |> dashboards_for_locale()
  end

  @doc false
  def dashboards_for_locale(locale) do
    titles = Map.get(@dashboard_locale_packs, locale)
    localized? = not is_nil(titles)
    titles = titles || %{}

    @dashboards
    |> Enum.map(fn dashboard ->
      uid = dashboard["uid"]

      %{
        "title" => Map.get(titles, dashboard["slug"], dashboard["title"]),
        "uid" => if(localized?, do: "#{uid}-#{locale}", else: uid)
      }
    end)
    |> Enum.sort_by(& &1["title"])
  end
end
