defmodule TeslaMateWeb.SettingsLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Settings, Locations, Repo}

  describe "global settings" do
    test "shows km and C by default", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "km"}, {"selected", "selected"}], ["km"]},
                  {"option", [{"value", "mi"}], ["mi"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_length")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "C"}, {"selected", "selected"}], ["°C"]},
                  {"option", [{"value", "F"}], ["°F"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_temperature")
    end

    test "shows :ideal by default", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "ideal"}, {"selected", "selected"}], ["ideal"]},
                  {"option", [{"value", "rated"}], ["rated"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_preferred_range")
    end

    test "changes base_url", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/settings")

      assert render_change(view, :change, %{global_settings: %{base_url: nil}})
             |> Floki.parse_document!()
             |> Floki.find("#global_settings_base_url")
             |> Floki.attribute("value") == []

      assert Settings.get_global_settings!().base_url == nil

      assert render_change(view, :change, %{
               global_settings: %{base_url: " https://example.com/  "}
             })
             |> Floki.parse_document!()
             |> Floki.find("#global_settings_base_url")
             |> Floki.attribute("value") == ["https://example.com"]

      assert Settings.get_global_settings!().base_url == "https://example.com"
    end

    test "changes grafana_url", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/settings")

      assert render_change(view, :change, %{global_settings: %{grafana_url: nil}})
             |> Floki.parse_document!()
             |> Floki.find("#global_settings_grafana_url")
             |> Floki.attribute("value") == []

      assert Settings.get_global_settings!().grafana_url == nil

      assert render_change(view, :change, %{
               global_settings: %{grafana_url: " https://example.com/  "}
             })
             |> Floki.parse_document!()
             |> Floki.find("#global_settings_grafana_url")
             |> Floki.attribute("value") == ["https://example.com"]

      assert Settings.get_global_settings!().grafana_url == "https://example.com"
    end

    test "reacts to change events", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "km"}], ["km"]},
                  {"option", [{"value", "mi"}, {"selected", "selected"}], ["mi"]}
                ]}
             ] =
               render_change(view, :change, %{global_settings: %{unit_of_length: :mi}})
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_length")

      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_length == :mi

      assert [
               {"select", _,
                [
                  {"option", [{"value", "C"}], ["°C"]},
                  {"option", [{"value", "F"}, {"selected", "selected"}], ["°F"]}
                ]}
             ] =
               render_change(view, :change, %{global_settings: %{unit_of_temperature: :F}})
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_temperature")

      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_temperature == :F
    end
  end

  describe "language" do
    alias Locations.Address

    test "changes language", %{conn: conn} do
      {:ok, %Address{id: address_id}} =
        Locations.create_address(%{
          display_name: "foo",
          name: "bar",
          latitude: 0,
          longitude: 0,
          osm_id: 0,
          osm_type: "way",
          raw: %{}
        })

      assert {:ok, view, html} = live(conn, "/settings")

      assert [{"option", [{"value", "en"}, {"selected", "selected"}], ["English"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_language option[selected]")

      render_change(view, :change, %{global_settings: %{language: "de"}})

      TestHelper.eventually(fn ->
        assert [{"option", [{"value", "de"}, {"selected", "selected"}], ["German"]}] =
                 render(view)
                 |> Floki.parse_document!()
                 |> Floki.find("#global_settings_language option[selected]")

        assert %Address{country: "de"} = Repo.get(Address, address_id)
      end)
    end

    @tag :capture_log
    test "shows error", %{conn: conn} do
      {:ok, %Address{id: address_id}} =
        Locations.create_address(%{
          display_name: "error",
          name: "bar",
          latitude: 0,
          longitude: 0,
          osm_id: 0,
          osm_type: "way",
          raw: %{}
        })

      assert {:ok, view, html} = live(conn, "/settings")

      assert [{"option", [{"value", "en"}, {"selected", "selected"}], ["English"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_language option[selected]")

      render_change(view, :change, %{global_settings: %{language: "de"}})

      TestHelper.eventually(fn ->
        html = render(view)

        assert "There was a problem retrieving data from OpenStreetMap. Please try again later." =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find("form .field-body")
                 |> Enum.find(
                   &match?(
                     {"div", _,
                      [
                        {_, _,
                         [
                           {_, _,
                            [{_, _, [{"select", [{"id", "global_settings_language"}, _], _}]}]},
                           _
                         ]}
                      ]},
                     &1
                   )
                 )
                 |> Floki.find("p.help")
                 |> Floki.text()

        assert [{"option", [{"value", "en"}, {"selected", "selected"}], ["English"]}] =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find("#global_settings_language option[selected]")

        assert %Address{
                 display_name: "error",
                 name: "bar",
                 latitude: 0.0,
                 longitude: 0.0,
                 osm_id: 0,
                 osm_type: "way",
                 raw: %{}
               } = Repo.get(Address, address_id)
      end)
    end
  end

  describe "car settings" do
    alias TeslaMate.Log

    defp car_fixture(attrs \\ %{}) do
      {:ok, car} =
        attrs
        |> Enum.into(%{
          efficiency: 0.153,
          eid: 42,
          model: "S",
          vid: 42,
          name: "foo",
          trim_badging: "P100D",
          vin: "12345F"
        })
        |> Log.create_car()

      car
    end

    test "Greys out input fields if sleep mode is disabled", %{conn: conn} do
      car = car_fixture()

      ids = [
        "#car_settings_#{car.id}_suspend_min",
        "#car_settings_#{car.id}_suspend_after_idle_min",
        "#car_settings_#{car.id}_req_no_shift_state_reading",
        "#car_settings_#{car.id}_req_no_temp_reading",
        "#car_settings_#{car.id}_req_not_unlocked"
      ]

      assert {:ok, view, html} = live(conn, "/settings")

      assert ["checked"] ==
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_sleep_mode_enabled")
               |> Floki.attribute("checked")

      html =
        render_change(view, :change, %{"car_settings_#{car.id}" => %{sleep_mode_enabled: false}})

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_sleep_mode_enabled")
               |> Floki.attribute("checked")

      for id <- ids do
        assert ["disabled"] =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find(id)
                 |> Floki.attribute("disabled")
      end

      html =
        render_change(view, :change, %{"car_settings_#{car.id}" => %{sleep_mode_enabled: true}})
        |> Floki.parse_document!()

      assert ["checked"] =
               html
               |> Floki.find("#car_settings_#{car.id}_sleep_mode_enabled")
               |> Floki.attribute("checked")

      for id <- ids do
        assert [] = html |> Floki.find(id) |> Floki.attribute("disabled")
      end
    end

    test "shows 21 and 15 minutes by default", %{conn: conn} do
      car = car_fixture()

      assert {:ok, _view, html} = live(conn, "/settings")
      html = Floki.parse_document!(html)

      assert [
               {"select", _,
                [
                  {"option", [{"value", "12"}], ["12 min"]},
                  {"option", [{"value", "15"}], ["15 min"]},
                  {"option", [{"value", "18"}], ["18 min"]},
                  {"option", [{"value", "21"}, {"selected", "selected"}], ["21 min"]},
                  {"option", [{"value", "24"}], ["24 min"]},
                  {"option", [{"value", "27"}], ["27 min"]},
                  {"option", [{"value", "30"}], ["30 min"]},
                  {"option", [{"value", "35"}], ["35 min"]},
                  {"option", [{"value", "40"}], ["40 min"]},
                  {"option", [{"value", "45"}], ["45 min"]},
                  {"option", [{"value", "50"}], ["50 min"]},
                  {"option", [{"value", "55"}], ["55 min"]},
                  {"option", [{"value", "60"}], ["60 min"]},
                  {"option", [{"value", "65"}], ["65 min"]},
                  {"option", [{"value", "70"}], ["70 min"]},
                  {"option", [{"value", "75"}], ["75 min"]},
                  {"option", [{"value", "80"}], ["80 min"]},
                  {"option", [{"value", "85"}], ["85 min"]},
                  {"option", [{"value", "90"}], ["90 min"]}
                ]}
             ] = Floki.find(html, "#car_settings_#{car.id}_suspend_min")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "5"}], ["5 min"]},
                  {"option", [{"value", "10"}], ["10 min"]},
                  {"option", [{"value", "15"}, {"selected", "selected"}], ["15 min"]},
                  {"option", [{"value", "20"}], ["20 min"]},
                  {"option", [{"value", "25"}], ["25 min"]},
                  {"option", [{"value", "30"}], ["30 min"]},
                  {"option", [{"value", "35"}], ["35 min"]},
                  {"option", [{"value", "40"}], ["40 min"]},
                  {"option", [{"value", "45"}], ["45 min"]},
                  {"option", [{"value", "50"}], ["50 min"]},
                  {"option", [{"value", "55"}], ["55 min"]},
                  {"option", [{"value", "60"}], ["60 min"]}
                ]}
             ] = Floki.find(html, "#car_settings_#{car.id}_suspend_after_idle_min")
    end

    test "shows false, false, true by default", %{conn: conn} do
      car =
        car_fixture(
          settings: %{
            req_no_shift_state_reading: false,
            req_no_temp_reading: false,
            req_not_unlocked: true
          }
        )

      assert {:ok, _view, html} = live(conn, "/settings")
      html = Floki.parse_document!(html)

      assert [] =
               html
               |> Floki.find("#car_settings_#{car.id}_req_no_shift_state_reading")
               |> Floki.attribute("checked")

      assert [] =
               html
               |> Floki.find("#car_settings_#{car.id}_req_no_temp_reading")
               |> Floki.attribute("checked")

      assert ["checked"] =
               html
               |> Floki.find("#car_settings_#{car.id}_req_not_unlocked")
               |> Floki.attribute("checked")
    end

    test "reacts to change events", %{conn: conn} do
      car =
        car_fixture(
          settings: %{
            suspend_min: 21,
            suspend_after_idle_min: 15,
            req_no_shift_state_reading: false,
            req_no_temp_reading: false,
            req_not_unlocked: true,
            free_supercharging: false
          }
        )

      assert {:ok, view, html} = live(conn, "/settings")

      assert [{"option", [{"value", "90"}, {"selected", "selected"}], ["90 min"]}] =
               render_change(view, :change, %{"car_settings_#{car.id}" => %{suspend_min: 90}})
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_suspend_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))

      assert [settings] = Settings.get_car_settings()
      assert settings.suspend_min == 90

      assert [{"option", [{"value", "30"}, {"selected", "selected"}], ["30 min"]}] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{suspend_after_idle_min: 30}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_suspend_after_idle_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))

      assert [settings] = Settings.get_car_settings()
      assert settings.suspend_after_idle_min == 30

      assert ["checked"] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{req_no_shift_state_reading: true}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_req_no_shift_state_reading")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.req_no_shift_state_reading == true

      assert ["checked"] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{req_no_temp_reading: true}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_req_no_temp_reading")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.req_no_temp_reading == true

      assert [] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{req_not_unlocked: false}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_req_not_unlocked")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.req_not_unlocked == false

      ## Charge cost

      assert [] ==
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_free_supercharging")
               |> Floki.attribute("checked")

      assert ["checked"] ==
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{free_supercharging: true}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_free_supercharging")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.free_supercharging == true
    end

    test "changes between cars", %{conn: conn} do
      one = car_fixture(id: 10001, name: "one", eid: 10001, vid: 1001, vin: "10001")
      two = car_fixture(id: 10002, name: "two", eid: 10002, vid: 1002, vin: "10002")

      assert {:ok, view, html} = live(conn, "/settings")

      assert one.name ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".tabs .is-active")
               |> Floki.text()

      # change settings of car "one"

      assert [{"option", [{"value", "90"}, {"selected", "selected"}], ["90 min"]}] =
               render_change(view, :change, %{"car_settings_#{one.id}" => %{suspend_min: 90}})
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{one.id}_suspend_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))

      assert [settings, _] = Settings.get_car_settings()
      assert settings.suspend_min == 90

      # change car

      render_click(view, :car, %{id: two.id})
      assert_redirect(view, path = "/settings?car=" <> id)
      assert id == to_string(two.id)
      assert {:ok, view, html} = live(conn, path)

      assert two.name ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".tabs .is-active")
               |> Floki.text()

      assert [{"option", [{"value", "21"}, {"selected", "selected"}], ["21 min"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{two.id}_suspend_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))

      # change settings of car "two"

      assert [{"option", [{"value", "60"}, {"selected", "selected"}], ["60 min"]}] =
               render_click(view, :change, %{"car_settings_#{two.id}" => %{suspend_min: 60}})
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{two.id}_suspend_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))

      # change back

      render_click(view, :car, %{id: one.id})
      assert_redirect(view, path = "/settings?car=" <> id)
      assert id == to_string(one.id)
      assert {:ok, view, html} = live(conn, path)

      assert one.name ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".tabs .is-active")
               |> Floki.text()

      assert [{"option", [{"value", "90"}, {"selected", "selected"}], ["90 min"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{one.id}_suspend_min option")
               |> Enum.filter(&match?({_, [_, {"selected", "selected"}], _}, &1))
    end
  end
end
