defmodule TeslaMateWeb.SettingsRenameLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Log, Settings, Repo}

  defp car_fixture(attrs) do
    attrs =
      Enum.into(attrs, %{
        efficiency: 0.153,
        eid: 42,
        model: "S",
        vid: 42,
        name: "foo",
        trim_badging: "P100D",
        vin: "12345F",
        settings: %{}
      })

    {:ok, car} = Log.create_car(attrs)

    {:ok, _} =
      car
      |> Settings.get_car_settings!()
      |> Settings.update_car_settings(attrs.settings)

    car
  end

  test "shows VIN for cars without a name", %{conn: conn} do
    unnamed =
      car_fixture(%{
        name: nil,
        eid: 1,
        vid: 1,
        vin: "5YJ3E1EA1KF000001",
        display_priority: 1
      })

    _named = car_fixture(%{name: "named", eid: 2, vid: 2, vin: "2", display_priority: 2})

    assert {:ok, _view, html} = live(conn, "/settings")
    html = Floki.parse_document!(html)

    vin_label = "5YJ3E1EA1KF000001"

    assert Floki.find(html, ".tabs li") |> Enum.map(&Floki.text/1) == [vin_label, "named"]

    assert Floki.find(html, ".car-order-row .label") |> Enum.map(&Floki.text/1) ==
             [vin_label, "named"]

    assert Floki.attribute(Floki.find(html, "#car_name_#{unnamed.id}_name"), "placeholder") ==
             [vin_label]
  end

  test "renames a car and updates tabs and car order labels", %{conn: conn} do
    unnamed =
      car_fixture(%{
        name: nil,
        eid: 1,
        vid: 1,
        vin: "5YJ3E1EA1KF000001",
        display_priority: 1
      })

    _named = car_fixture(%{name: "named", eid: 2, vid: 2, vin: "2", display_priority: 2})

    assert {:ok, view, _html} = live(conn, "/settings?car=#{unnamed.id}")

    html =
      render_change(view, :rename_car, %{"id" => to_string(unnamed.id), "car" => %{"name" => "  Garage  "}})
      |> Floki.parse_document!()

    assert Floki.find(html, ".tabs li") |> Enum.map(&Floki.text/1) == ["Garage", "named"]

    assert Floki.find(html, ".car-order-row .label") |> Enum.map(&Floki.text/1) ==
             ["Garage", "named"]

    assert Floki.attribute(Floki.find(html, "#car_name_#{unnamed.id}_name"), "value") ==
             ["Garage"]

    assert Repo.get!(TeslaMate.Log.Car, unnamed.id).name == "Garage"

    html =
      render_change(view, :rename_car, %{"id" => to_string(unnamed.id), "car" => %{"name" => "   "}})
      |> Floki.parse_document!()

    vin_label = "5YJ3E1EA1KF000001"

    assert Floki.find(html, ".tabs li") |> Enum.map(&Floki.text/1) == [vin_label, "named"]

    assert Floki.find(html, ".car-order-row .label") |> Enum.map(&Floki.text/1) ==
             [vin_label, "named"]

    assert Repo.get!(TeslaMate.Log.Car, unnamed.id).name == nil
  end
end
