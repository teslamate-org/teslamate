defmodule TeslaMateWeb.MaintenanceLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Log
  alias TeslaMate.Log.{ChargingProcess, Drive, Position}
  alias TeslaMate.Repo

  test "shows the scoped read-only empty state", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/maintenance")

    assert has_element?(view, "#maintenance-read-only")
    assert has_element?(view, "#maintenance-summary")
    assert has_element?(view, "#maintenance-empty")
    assert has_element?(view, "#maintenance-refresh[phx-click=refresh]")
    refute has_element?(view, "#maintenance-findings")

    assert html =~ "Read-only. TeslaMate has not changed any data."
    assert html =~ "No long-running open drives or charging sessions found."
    assert html =~ ~s(href="/maintenance")
  end

  test "shows long-running sessions without claiming corruption", %{conn: conn} do
    now = DateTime.utc_now()
    car = car_fixture(%{name: "Atlas"})

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(now, -3 * 24 * 60 * 60, :second)
      )

    long_running_charging_process =
      charging_process_fixture(car,
        start_date: DateTime.add(now, -4 * 24 * 60 * 60, :second)
      )

    recent_drive =
      drive_fixture(car,
        start_date: DateTime.add(now, -60, :second)
      )

    assert {:ok, view, _html} = live(conn, "/maintenance")

    assert has_element?(
             view,
             "#finding-drive-#{long_running_drive.id}[data-finding-code=long_running_open_drive]"
           )

    assert has_element?(
             view,
             "#finding-charging_process-#{long_running_charging_process.id}[data-finding-code=long_running_open_charging_process]"
           )

    refute has_element?(view, "#finding-drive-#{recent_drive.id}")
    refute has_element?(view, "#maintenance-empty")

    html = render(view)
    assert html =~ "Atlas"
    assert html =~ "Drive ##{long_running_drive.id}"
    assert html =~ "Charging session ##{long_running_charging_process.id}"
    assert html =~ "A long-running session is not automatically corrupt."
  end

  test "refreshes the report without exposing maintenance mutations", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/maintenance")
    assert has_element?(view, "#maintenance-empty")

    car = car_fixture()

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(DateTime.utc_now(), -3 * 24 * 60 * 60, :second)
      )

    view
    |> element("#maintenance-refresh")
    |> render_click()

    assert has_element?(view, "#finding-drive-#{long_running_drive.id}")
    refute has_element?(view, "#maintenance-empty")

    html = render(view) |> Floki.parse_document!()

    assert ["refresh"] ==
             html
             |> Floki.find("button[phx-click]")
             |> Floki.attribute("phx-click")

    assert [] == Floki.find(html, "form")
    assert [] == Floki.find(html, "[phx-click=close], [phx-click=delete], [phx-click=repair]")
  end

  defp car_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          eid: unique,
          vid: unique,
          vin: "maintenance-#{unique}",
          model: "3"
        },
        attrs
      )

    {:ok, car} = Log.create_car(attrs)
    car
  end

  defp drive_fixture(car, attrs) do
    attrs = Enum.into(attrs, %{car_id: car.id})
    Repo.insert!(struct!(Drive, attrs))
  end

  defp charging_process_fixture(car, attrs) do
    attrs = Enum.into(attrs, %{car_id: car.id})

    position =
      Repo.insert!(%Position{
        car_id: car.id,
        date: Map.fetch!(attrs, :start_date),
        latitude: Decimal.new("0"),
        longitude: Decimal.new("0")
      })

    attrs = Map.put(attrs, :position_id, position.id)
    Repo.insert!(struct!(ChargingProcess, attrs))
  end
end
