defmodule TeslaMateWeb.ImportLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Import, Repair}

  test "imports files", %{conn: conn} do
    {:ok, _} = start_supervised({Import, directory: "./test/fixtures/import/01_complete"})
    {:ok, _} = start_supervised(Repair)

    assert {:ok, view, html} = live(conn, "/import")

    # Table
    assert [
             {"tr", _, [{"td", _, ["06/2016"]}, {"td", _, [path_00]}, _]},
             {"tr", _, [{"td", _, ["07/2016"]}, {"td", _, [path_01]}, _]}
           ] =
             html
             |> Floki.parse_document!()
             |> Floki.find("table tr")

    assert String.ends_with?(path_00, "/test/fixtures/import/01_complete/TeslaFi62016.csv")
    assert String.ends_with?(path_01, "/test/fixtures/import/01_complete/TeslaFi72016.csv")

    # Time Zone

    assert html
           |> Floki.parse_document!()
           |> Floki.find("#settings_timezone option")
           |> Enum.find(fn {"option", _, [label]} -> label == "Europe/Berlin" end)

    assert render_change(view, :change, %{settings: %{timezone: "America/Los_Angeles"}})
           |> Floki.parse_document!()
           |> Floki.find("#settings_timezone option[selected]")
           |> Floki.attribute("value") == ["America/Los_Angeles"]

    # Import!

    assert [
             {"tr", [],
              [
                {"td", _, ["06/2016"]},
                {"td", _, [_]},
                {"td", _, [{"span", _, [{"span", [{"class", "is-loading"}], _}]}]}
              ]},
             {"tr", _,
              [
                {"td", _, ["07/2016"]},
                {"td", _, [_]},
                {"td", _, [{"span", _, [{"span", [{"class", "is-loading"}], []}]}]}
              ]}
           ] =
             render_submit(view, :import, %{settings: %{timezone: "America/Los_Angeles"}})
             |> Floki.parse_document!()
             |> Floki.find("table tr")

    TestHelper.eventually(
      fn ->
        assert [
                 {"tr", [],
                  [
                    {"td", _, ["06/2016"]},
                    {"td", _, [_]},
                    {"td", _,
                     [
                       {"span", _,
                        [
                          {"span", [{"class", "icon has-text-success"}],
                           [{"span", [{"class", "mdi mdi-check-bold"}], _}]}
                        ]}
                     ]}
                  ]},
                 {"tr", [],
                  [
                    {"td", _, ["07/2016"]},
                    {"td", _, [_]},
                    {"td", _,
                     [
                       {"span", _,
                        [
                          {"span", [{"class", "icon has-text-success"}],
                           [{"span", [{"class", "mdi mdi-check-bold"}], _}]}
                        ]}
                     ]}
                  ]}
               ] =
                 render(view)
                 |> Floki.parse_document!()
                 |> Floki.find("table tr")
      end,
      delay: 250,
      attempts: 10
    )
  end
end
