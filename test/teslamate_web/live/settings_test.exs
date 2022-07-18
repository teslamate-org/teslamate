defmodule TeslaMateWeb.SettingsLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Settings, Locations, Repo}

  import TestHelper, only: [decimal: 1]

  describe "units" do
    test "unit of length: shows 'km' by default", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"selected", "selected"}, {"value", "km"}], ["km"]},
                  {"option", [{"value", "mi"}], ["mi"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_length")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "km"}], ["km"]},
                  {"option", [{"selected", "selected"}, {"value", "mi"}], ["mi"]}
                ]}
             ] =
               render_change(view, :change, %{global_settings: %{unit_of_length: :mi}})
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_length")

      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_length == :mi
    end

    test "unit of temperature: shows '°C' by default", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"selected", "selected"}, {"value", "C"}], ["°C"]},
                  {"option", [{"value", "F"}], ["°F"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_temperature")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "C"}], ["°C"]},
                  {"option", [{"selected", "selected"}, {"value", "F"}], ["°F"]}
                ]}
             ] =
               render_change(view, :change, %{global_settings: %{unit_of_temperature: :F}})
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_temperature")

      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_temperature == :F
    end

    test "unit of pressure: shows 'bar' by default", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"selected", "selected"}, {"value", "bar"}], ["bar"]},
                  {"option", [{"value", "psi"}], ["psi"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_pressure")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "bar"}], ["bar"]},
                  {"option", [{"selected", "selected"}, {"value", "psi"}], ["psi"]}
                ]}
             ] =
               render_change(view, :change, %{global_settings: %{unit_of_pressure: :psi}})
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_unit_of_pressure")

      assert settings = Settings.get_global_settings!()
      assert settings.unit_of_pressure == :psi
    end
  end

  describe "global settings" do
    test "shows :rated by default", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, "/settings")

      assert [
               {"select", _,
                [
                  {"option", [{"value", "ideal"}], ["ideal"]},
                  {"option", [{"selected", "selected"}, {"value", "rated"}], ["rated"]}
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

      assert [{"option", [{"selected", "selected"}, {"value", "en"}], ["English"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_language option[selected]")

      render_change(view, :change, %{global_settings: %{language: "de"}})

      TestHelper.eventually(fn ->
        assert [{"option", [{"selected", "selected"}, {"value", "de"}], ["German"]}] =
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

      assert [{"option", [{"selected", "selected"}, {"value", "en"}], ["English"]}] =
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

        assert [{"option", [{"selected", "selected"}, {"value", "en"}], ["English"]}] =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find("#global_settings_language option[selected]")

        assert %Address{
                 display_name: "error",
                 name: "bar",
                 latitude: decimal("0.000000"),
                 longitude: decimal("0.000000"),
                 osm_id: 0,
                 osm_type: "way",
                 raw: %{}
               } = Repo.get(Address, address_id)
      end)
    end

    test "adds a query param when changing the UI language", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/settings")

      assert [{"option", [{"selected", "selected"}, {"value", "en"}], ["English"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_ui option[selected]")

      render_change(view, :change, %{global_settings: %{ui: "de"}})
      assert_redirect(view, path = "/settings?locale=de")

      assert {:ok, _view, html} = live(conn, path)

      assert [{"option", [{"selected", "selected"}, {"value", "de"}], ["German"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#global_settings_ui option[selected]")
    end
  end

  describe "car settings" do
    alias TeslaMate.{Log, Settings}

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

    test "hides most of the sleep mode settings if streaming is enabled", %{conn: conn} do
      car = car_fixture(settings: %{use_streaming_api: true})

      assert {:ok, _view, html} = live(conn, "/settings")
      html = Floki.parse_document!(html)

      assert [] = Floki.find(html, "#car_settings_#{car.id}_suspend_min")
      assert [] = Floki.find(html, "#car_settings_#{car.id}_suspend_after_idle_min")

      assert [] =
               html
               |> Floki.find("#car_settings_#{car.id}_req_not_unlocked")
               |> Floki.attribute("checked")
    end

    test "shows 21 and 15 minutes by default if streaming is disabled", %{conn: conn} do
      car = car_fixture(settings: %{use_streaming_api: false})

      assert {:ok, _view, html} = live(conn, "/settings")
      html = Floki.parse_document!(html)

      assert [
               {"option", [{"value", "12"}], ["12 min"]},
               {"option", [{"value", "15"}], ["15 min"]},
               {"option", [{"value", "18"}], ["18 min"]},
               {"option", [{"selected", "selected"}, {"value", "21"}], ["21 min"]},
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
             ] = Floki.find(html, "#car_settings_#{car.id}_suspend_min option")

      assert [
               {"option", [{"value", "3"}], ["3 min"]},
               {"option", [{"value", "5"}], ["5 min"]},
               {"option", [{"value", "10"}], ["10 min"]},
               {"option", [{"selected", "selected"}, {"value", "15"}], ["15 min"]},
               {"option", [{"value", "20"}], ["20 min"]},
               {"option", [{"value", "25"}], ["25 min"]},
               {"option", [{"value", "30"}], ["30 min"]},
               {"option", [{"value", "35"}], ["35 min"]},
               {"option", [{"value", "40"}], ["40 min"]},
               {"option", [{"value", "45"}], ["45 min"]},
               {"option", [{"value", "50"}], ["50 min"]},
               {"option", [{"value", "55"}], ["55 min"]},
               {"option", [{"value", "60"}], ["60 min"]}
             ] = Floki.find(html, "#car_settings_#{car.id}_suspend_after_idle_min option")
    end

    test "By default, the vehicle must be locked to fall asleep", %{conn: conn} do
      car = car_fixture(settings: %{req_not_unlocked: true})

      assert {:ok, _view, html} = live(conn, "/settings")
      html = Floki.parse_document!(html)

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
            req_not_unlocked: true,
            free_supercharging: false,
            use_streaming_api: false
          }
        )

      assert {:ok, view, _html} = live(conn, "/settings")

      assert [{"option", [{"selected", "selected"}, {"value", "90"}], ["90 min"]}] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{suspend_min: 90, use_streaming_api: false}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_suspend_min option[selected]")

      assert [settings] = Settings.get_car_settings()
      assert settings.suspend_min == 90

      assert [{"option", [{"selected", "selected"}, {"value", "30"}], ["30 min"]}] =
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{
                   suspend_after_idle_min: 30,
                   use_streaming_api: false
                 }
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_suspend_after_idle_min option[selected]")

      assert [settings] = Settings.get_car_settings()
      assert settings.suspend_after_idle_min == 30

      html =
        render_change(view, :change, %{"car_settings_#{car.id}" => %{req_not_unlocked: false}})
        |> Floki.parse_document!()

      assert [] =
               html
               |> Floki.find("#car_settings_#{car.id}_req_not_unlocked")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.req_not_unlocked == false

      ## Charge cost

      assert [] ==
               html
               |> Floki.find("#car_settings_#{car.id}_free_supercharging")
               |> Floki.attribute("checked")

      html =
        render_change(view, :change, %{"car_settings_#{car.id}" => %{free_supercharging: true}})
        |> Floki.parse_document!()

      assert ["checked"] ==
               html
               |> Floki.find("#car_settings_#{car.id}_free_supercharging")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.free_supercharging == true

      ## Streaming API

      assert [] ==
               html
               |> Floki.find("#car_settings_#{car.id}_use_streaming_api")
               |> Floki.attribute("checked")

      assert ["checked"] ==
               render_change(view, :change, %{
                 "car_settings_#{car.id}" => %{use_streaming_api: true}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{car.id}_use_streaming_api")
               |> Floki.attribute("checked")

      assert [settings] = Settings.get_car_settings()
      assert settings.use_streaming_api == true
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

      assert [{"option", [{"selected", "selected"}, {"value", "90"}], ["90 min"]}] =
               render_change(view, :change, %{
                 "car_settings_#{one.id}" => %{suspend_min: 90, use_streaming_api: false}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{one.id}_suspend_min option[selected]")

      assert [settings, _] = Settings.get_car_settings()
      assert settings.suspend_min == 90

      # change car
      view
      |> element(".tabs li a", two.name)
      |> render_click()

      assert_redirect(view, path = "/settings?car=#{two.id}")
      assert {:ok, view, html} = live(conn, path)

      assert two.name ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".tabs .is-active")
               |> Floki.text()

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{one.id}_suspend_min option[selected]")

      # change settings of car "two"

      assert [{"option", [{"selected", "selected"}, {"value", "60"}], ["60 min"]}] =
               render_change(view, :change, %{
                 "car_settings_#{two.id}" => %{suspend_min: 60, use_streaming_api: false}
               })
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{two.id}_suspend_min option[selected]")

      # change back

      view
      |> element(".tabs li a", one.name)
      |> render_click()

      assert_redirect(view, path = "/settings?car=#{one.id}")
      assert {:ok, _view, html} = live(conn, path)

      assert one.name ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".tabs .is-active")
               |> Floki.text()

      assert [{"option", [{"selected", "selected"}, {"value", "90"}], ["90 min"]}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car_settings_#{one.id}_suspend_min option[selected]")
    end
  end

  describe "updates" do
    alias TeslaMate.Updater

    import Mock

    def github_mock do
      release = %{"tag_name" => "v1.1.3", "prerelease" => false, "draft" => false}
      resp = %Tesla.Env{status: 200, body: release}
      {Tesla.Adapter.Finch, [], call: fn _, _ -> {:ok, resp} end}
    end

    test "informs if an update is available", %{conn: conn} do
      with_mocks [github_mock()] do
        _pid = start_supervised!({Updater, version: "1.0.0", check_after: 0})

        Process.sleep(1000)

        assert {:ok, _view, html} = live(conn, "/settings")
        html = Floki.parse_document!(html)

        assert "#{Application.spec(:teslamate, :vsn)} (Update available: 1.1.3)" ==
                 html
                 |> Floki.find(".about tr:first-child td")
                 |> Floki.text()

        assert [
                 {"a",
                  [_, {"href", "https://github.com/adriankumpf/teslamate/releases"}, _, _, _],
                  [_, {_, _, ["Update available: 1.1.3"]}]}
               ] =
                 Floki.find(html, ".footer a")
                 |> Enum.reject(&match?({"a", [_, _, _, _, _], [_, {_, _, ["Donate"]}]}, &1))
      end
    end
  end

  describe "sign-out" do
    import Mock

    test "tba", %{conn: conn} do
      with_mocks [{TeslaMate.Api, [], signed_in?: fn -> true end, sign_out: fn -> :ok end}] do
        assert {:ok, view, _html} = live(conn, "/settings")

        view
        |> element("button", "Sign out")
        |> render_click()

        assert_redirect(view, "/")

        assert_called(TeslaMate.Api.sign_out())
      end
    end
  end
end
