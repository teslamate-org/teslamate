defmodule TeslaMateWeb.SettingsRenameLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Log, Settings}
  alias TeslaMateWeb.CarLive.Summary

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

  defp summary_title(name, vin) do
    {title, _vin_label} = Summary.format_car_title(name, vin)
    title
  end

  test "unnamed cars use the same title as the car summary", %{conn: conn} do
    vin = "5YJ3E1EA1KF000001"

    _unnamed =
      car_fixture(%{
        name: nil,
        eid: 1,
        vid: 1,
        vin: vin,
        display_priority: 1
      })

    _blank =
      car_fixture(%{
        name: "",
        eid: 3,
        vid: 3,
        vin: "5YJSA1E26HF000003",
        display_priority: 3
      })

    _named =
      car_fixture(%{
        name: "named",
        eid: 2,
        vid: 2,
        vin: "5YJ3E1EB1KF000002",
        display_priority: 2
      })

    assert {:ok, _view, html} = live(conn, "/settings")
    html = Floki.parse_document!(html)

    nil_title = summary_title(nil, vin)
    blank_title = summary_title("", "5YJSA1E26HF000003")

    assert nil_title == "VIN " <> vin
    assert blank_title == "VIN 5YJSA1E26HF000003"

    assert Floki.find(html, ".tabs li") |> Enum.map(&Floki.text/1) == [
             nil_title,
             "named",
             blank_title
           ]

    assert Floki.find(html, ".car-order-row .label") |> Enum.map(&Floki.text/1) == [
             nil_title,
             "named",
             blank_title
           ]

    assert html |> Floki.find("input[name='car[name]']") == []
    refute Floki.text(html) =~ "???"
  end
end
