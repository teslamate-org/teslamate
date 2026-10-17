defmodule TeslaMateWeb.LayoutViewTest do
  use TeslaMateWeb.ConnCase, async: true

  alias TeslaMateWeb.LayoutView

  describe "dashboards_for_locale/1" do
    test "uses Italian dashboard titles and locale-specific UIDs" do
      dashboards = LayoutView.dashboards_for_locale("it")

      assert %{"title" => "Panoramica", "uid" => "kOuP_Fggz-it"} in dashboards
      refute Enum.any?(dashboards, &(&1["uid"] == "kOuP_Fggz"))
    end

    test "falls back to original dashboards when no locale pack exists" do
      dashboards = LayoutView.dashboards_for_locale("de")

      assert %{"title" => "Overview", "uid" => "kOuP_Fggz"} in dashboards
      assert %{"title" => "States", "uid" => "xo4BNRkZz"} in dashboards
      refute Enum.any?(dashboards, &String.ends_with?(&1["uid"], "-de"))
    end
  end
end
