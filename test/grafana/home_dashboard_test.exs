defmodule TeslaMate.Grafana.HomeDashboardTest do
  use ExUnit.Case, async: true

  @dashboard_path "grafana/dashboards/internal/home.json"

  setup_all do
    json = File.read!(@dashboard_path)

    {:ok, dashboard: Jason.decode!(json), json: json}
  end

  test "contains only the dashboard list and image panels", %{dashboard: dashboard, json: json} do
    assert dashboard["title"] == "Home"
    assert Enum.map(dashboard["panels"], & &1["type"]) == ["dashlist", "text"]
    assert get_in(dashboard, ["panels", Access.at(1), "options", "content"]) =~ "background-image"

    refute Enum.any?(dashboard["panels"], &(&1["type"] == "news"))
    refute json =~ "api.cors.lol"
  end

  test "panels fill the 24-column grid without gaps, overlaps, or overflow", %{
    dashboard: dashboard
  } do
    final_x =
      dashboard["panels"]
      |> Enum.sort_by(& &1["gridPos"]["x"])
      |> Enum.reduce(0, fn %{"gridPos" => %{"w" => width, "x" => x}}, expected_x ->
        assert width > 0
        assert x == expected_x
        assert x + width <= 24

        x + width
      end)

    assert final_x == 24
  end

  test "Dockerfile provisions the shipped dashboard as Grafana's home dashboard" do
    dockerfile = File.read!("grafana/Dockerfile")

    assert dockerfile =~
             "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/dashboards_internal/home.json"

    assert dockerfile =~ "COPY dashboards/internal/*.json /dashboards_internal/"
  end
end
