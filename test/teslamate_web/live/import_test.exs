defmodule TeslaMateWeb.ImportLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Import, Repair}
  alias TeslaMate.Import.Checkpoint

  test "imports files", %{conn: conn} do
    {:ok, _} = start_supervised({Import, directory: "./test/fixtures/import/01_complete"})
    {:ok, _} = start_supervised(Repair)

    assert {:ok, view, html} = live(conn, "/import")

    assert html =~ "unchanged completed files are skipped"
    assert html =~ "row-exact crash resume is not provided"

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

  test "shows a bounded safe report for malformed rows", %{conn: conn} do
    {:ok, _} = start_supervised({Import, directory: "./test/fixtures/import/08_resilient"})
    {:ok, _} = start_supervised(Repair)

    assert {:ok, view, _html} = live(conn, "/import")

    render_submit(view, :import, %{settings: %{timezone: "Etc/UTC"}})

    TestHelper.eventually(
      fn ->
        html = render(view)

        assert html =~ "Skipped 1 malformed row. Valid rows continued."
        assert html =~ "stored without source values"
        assert html =~ "survives an interrupted import"
        assert html =~ "TeslaFi12018.csv, row 3"
        assert html =~ "drive_state.latitude"
        assert html =~ "drive_state.longitude"
        refute html =~ "PRIVATE_COORDINATE_SENTINEL"
        refute html =~ "PRIVATE_LONGITUDE_SENTINEL"
      end,
      delay: 50,
      attempts: 100
    )
  end

  test "shows and submits the saved timezone for an interrupted run", %{conn: conn} do
    directory = "./test/fixtures/import/01_complete"

    assert {:ok, _run} =
             directory
             |> Checkpoint.source_key()
             |> Checkpoint.start_run("America/Los_Angeles")

    {:ok, _} = start_supervised({Import, directory: directory})

    assert {:ok, _view, html} = live(conn, "/import")

    assert html =~ "interrupted import will resume with its saved time zone"

    assert html
           |> Floki.parse_document!()
           |> Floki.find("#settings_resume_timezone")
           |> Floki.attribute("value") == ["America/Los_Angeles"]

    assert html
           |> Floki.parse_document!()
           |> Floki.find("#saved-import-timezone")
           |> Floki.text() =~ "America/Los_Angeles"

    refute html |> Floki.parse_document!() |> Floki.find("#settings_timezone") |> Enum.any?()
  end
end
