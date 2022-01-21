defmodule TeslaMateWeb.GeoFenceLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Locations, Settings, Log, Repo}
  alias TeslaMate.Locations.GeoFence

  import TestHelper, only: [decimal: 1]
  import Ecto.Query

  def geofence_fixture(attrs \\ %{}) do
    {:ok, address} =
      attrs
      |> Enum.into(%{radius: 100})
      |> Locations.create_geofence()

    address
  end

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

  describe "Index" do
    test "renders all geo-fences", %{conn: conn} do
      _gf1 =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      _gf2 =
        geofence_fixture(%{name: "Service Center", latitude: 52.394246, longitude: 13.542552})

      _gf3 =
        geofence_fixture(%{name: "Victory Column", latitude: 52.514521, longitude: 13.350144})

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert [
               _,
               ["Post office", "-25.066188, -130.100502", "100 m", _],
               ["Service Center", "52.394246, 13.542552", "100 m", _],
               ["Victory Column", "52.514521, 13.350144", "100 m", _]
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("tr")
               |> Enum.map(fn row -> row |> Floki.find("td") |> Enum.map(&Floki.text/1) end)
    end

    test "displays radius in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_global_settings!() |> Settings.update_global_settings(%{unit_of_length: :mi})

      _gf1 =
        geofence_fixture(%{
          name: "Post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 100
        })

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert ["Post office", "-25.066188, -130.100502", "328 ft", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end

    test "allows deletion of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Victory Column", latitude: 52.514521, longitude: 13.350144})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["Victory Column", "52.514521, 13.350144", "100 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)

      assert [{"a", _, _}] =
               html
               |> Floki.parse_document!()
               |> Floki.find("[data-id=#{id}]")

      assert [{"tbody", _, []}] =
               view
               |> render_click(:delete, %{"id" => "#{id}"})
               |> Floki.parse_document!()
               |> Floki.find("tbody")
    end
  end

  describe "Edit" do
    test "validates changes when editing of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{
          name: "Post office",
          latitude: -25.066188,
          longitude: -130.100502,
          billing_type: :per_kwh,
          cost_per_unit: 0.2599,
          session_fee: 5.49
        })

      assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")
      html = Floki.parse_document!(html)

      name = Floki.find(html, "#geo_fence_name")
      assert ["Post office"] = Floki.attribute(name, "value")

      latitude = Floki.find(html, "#geo_fence_latitude")
      assert ["-25.066188"] = Floki.attribute(latitude, "value")

      longitude = Floki.find(html, "#geo_fence_longitude")
      assert ["-130.100502"] = Floki.attribute(longitude, "value")

      radius = Floki.find(html, "#geo_fence_radius")
      assert ["100"] = Floki.attribute(radius, "value")

      radius = Floki.find(html, "#geo_fence_cost_per_unit")
      assert ["0.2599"] = Floki.attribute(radius, "value")

      radius = Floki.find(html, "#geo_fence_session_fee")
      assert ["5.49"] = Floki.attribute(radius, "value")

      html =
        render_submit(view, :save, %{geo_fence: %{name: "", radius: ""}})
        |> Floki.parse_document!()

      assert [""] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")

      for kind <- ["name", "radius"] do
        error_html =
          html
          |> Floki.find(".field-body .field")
          |> Enum.filter(fn field -> Floki.find(field, "#geo_fence_#{kind}") |> length() == 1 end)
          |> Floki.find("span")
          |> Floki.raw_html(encode: false)

        assert error_html ==
                 "<span class=\"help is-danger pl-15\" phx-feedback-for=\"geo_fence_#{kind}\">can't be blank</span>"
      end
    end

    test "allows editing of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")
      html = Floki.parse_document!(html)

      name = Floki.find(html, "#geo_fence_name")
      assert ["Post office"] = Floki.attribute(name, "value")

      latitude = Floki.find(html, "#geo_fence_latitude")
      assert ["-25.066188"] = Floki.attribute(latitude, "value")

      longitude = Floki.find(html, "#geo_fence_longitude")
      assert ["-130.100502"] = Floki.attribute(longitude, "value")

      radius = Floki.find(html, "#geo_fence_radius")
      assert ["100"] = Floki.attribute(radius, "value")

      render_submit(view, :save, %{
        geo_fence: %{name: "Adamstown", longitude: 0, latitude: 0, radius: 20}
      })

      assert_redirect(view, "/geo-fences")

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert ["Adamstown", "0.000000, 0.000000", "20 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end
  end

  describe "New" do
    test "pre-fills the coordinates with the most recent position", %{conn: conn} do
      car = car_fixture()

      assert {:ok, _} =
               Log.insert_position(car, %{
                 date: DateTime.utc_now(),
                 latitude: 48.067612,
                 longitude: 12.862226
               })

      assert {:ok, _view, html} = live(conn, "/geo-fences/new")
      html = Floki.parse_document!(html)

      latitude = Floki.find(html, "#geo_fence_latitude")
      longitude = Floki.find(html, "#geo_fence_longitude")

      assert ["48.067612"] = Floki.attribute(latitude, "value")
      assert ["12.862226"] = Floki.attribute(longitude, "value")
    end

    test "validates cahnges when creating a new geo-fence", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/geo-fences/new")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "",
            longitude: nil,
            latitude: nil,
            radius: "",
            billing_type: :per_kwh,
            cost_per_unit: "wat",
            session_fee: "wat"
          }
        })
        |> Floki.parse_document!()

      assert [""] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_radius") |> Floki.attribute("value")
      assert ["wat"] = html |> Floki.find("#geo_fence_cost_per_unit") |> Floki.attribute("value")
      assert ["wat"] = html |> Floki.find("#geo_fence_session_fee") |> Floki.attribute("value")

      assert [
               field_position,
               field_name,
               field_cost_per_unit,
               field_session_fee,
               _
             ] = Floki.find(html, ".field.is-horizontal")

      assert ["can't be blank", "can't be blank", "can't be blank"] =
               field_position |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert ["can't be blank"] = field_name |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert "Per kWh" =
               field_cost_per_unit
               |> Floki.find("#geo_fence_billing_type option[selected]")
               |> Floki.text()

      assert "is invalid" =
               field_cost_per_unit
               |> Floki.find("span.help")
               |> Floki.text()

      assert "is invalid" =
               field_session_fee
               |> Floki.find("span")
               |> Floki.text()

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "foo",
            longitude: "wot",
            latitude: "wat",
            radius: "40",
            billing_type: :per_minute,
            cost_per_unit: 0.25,
            session_fee: 4.79
          }
        })
        |> Floki.parse_document!()

      assert ["foo"] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")
      assert ["wat"] = html |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert ["wot"] = html |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")
      assert ["40"] = html |> Floki.find("#geo_fence_radius") |> Floki.attribute("value")
      assert ["0.25"] = html |> Floki.find("#geo_fence_cost_per_unit") |> Floki.attribute("value")
      assert ["4.79"] = html |> Floki.find("#geo_fence_session_fee") |> Floki.attribute("value")

      assert [
               field_position,
               field_name,
               field_cost_per_unit,
               field_session_fee,
               _
             ] = Floki.find(html, ".field.is-horizontal")

      assert ["is invalid", "is invalid"] =
               field_position |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert [] =
               field_name
               |> Floki.find("span")
               |> Enum.map(&Floki.text/1)

      assert "Per Minute" =
               field_cost_per_unit
               |> Floki.find("#geo_fence_billing_type option[selected]")
               |> Floki.text()

      assert "" =
               field_cost_per_unit
               |> Floki.find("span.help")
               |> Floki.text()

      assert "" =
               field_session_fee
               |> Floki.find("span")
               |> Floki.text()
    end

    test "creates a new geo-fence", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      # Default radius of 20m
      assert html
             |> Floki.parse_document!()
             |> Floki.find("#geo_fence_radius")
             |> Floki.attribute("value") == ["20"]

      render_submit(view, :save, %{
        geo_fence: %{
          name: "post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 25
        }
      })

      assert_redirect(view, "/geo-fences")

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.066188, -130.100502", "25 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end

    test "allows creating of a geo-fence with radius being displayed in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_global_settings!() |> Settings.update_global_settings(%{unit_of_length: :mi})

      assert {:ok, view, _html} = live(conn, "/geo-fences/new")

      render_submit(view, :save, %{
        geo_fence: %{
          name: "post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 15
        }
      })

      assert_redirect(view, "/geo-fences")

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.066188, -130.100502", "49 ft", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)

      {:ok, _settings} =
        Settings.get_global_settings!() |> Settings.update_global_settings(%{unit_of_length: :km})

      assert {:ok, _view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.066188, -130.100502", "15 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end
  end

  describe "grafana URL" do
    alias TeslaMate.Settings.GlobalSettings

    test "initiall sets the base URL", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      assert {:ok, _parent_view, _html} =
               conn
               |> put_connect_params(%{"referrer" => "http://grafana.example.com/d/xyz/12"})
               |> live("/geo-fences/new?lat=0.0&lng=0.0")

      assert %GlobalSettings{grafana_url: "http://grafana.example.com"} =
               Settings.get_global_settings!()
    end

    test "handles weird referrers", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      for referrer <- [nil, "", "example.com", "http://example.com", "http://example.com/"] do
        assert {:ok, _parent_view, _html} =
                 conn
                 |> put_connect_params(%{"referrer" => referrer})
                 |> live("/geo-fences/new?lat=0.0&lng=0.0")

        assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()
      end
    end

    test "keeps the path", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      assert {:ok, _parent_view, _html} =
               conn
               |> put_connect_params(%{"referrer" => "http://example.com:9090/grafana/d/xyz/12"})
               |> live("/geo-fences/new?lat=0.0&lng=0.0")

      assert %GlobalSettings{grafana_url: "http://example.com:9090/grafana"} =
               Settings.get_global_settings!()
    end

    test "does not update the base URL if exists already", %{conn: conn} do
      assert {:ok, _settings} =
               Settings.get_global_settings!()
               |> Settings.update_global_settings(%{grafana_url: "https://grafana.example.com"})

      assert {:ok, _parent_view, _html} =
               conn
               |> put_connect_params(%{"referrer" => "http://grafana.foo.com/d/xyz/12"})
               |> live("/geo-fences/new?lat=0.0&lng=0.0")

      assert %GlobalSettings{grafana_url: "https://grafana.example.com"} =
               Settings.get_global_settings!()
    end
  end

  describe "charging cost" do
    alias TeslaMate.Log.{ChargingProcess, Position}
    alias TeslaMate.Log

    test "shows modal if cost per kWh was entered", %{conn: conn} do
      car = car_fixture()

      lat = 47.81444104508753
      lng = 12.367612123489382

      params = %{
        name: "Supercharger",
        latitude: 47.814441,
        longitude: 12.367768,
        radius: 30,
        billing_type: :per_kwh,
        cost_per_unit: 0.33,
        session_fee: nil
      }

      # Does not show modal if there aren't any charging sessions at this location

      assert {:ok, view, _html} = live(conn, "/geo-fences/new")
      render_submit(view, :save, %{geo_fence: params})
      assert_redirect(view, "/geo-fences")

      # Insert charging sessions ...

      :ok = insert_charging_processes(car, {lat, lng})
      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      assert [] == html |> Floki.parse_document!() |> Floki.find(".modal.is-active")

      html =
        render_submit(view, :save, %{geo_fence: params})
        |> Floki.parse_document!()

      modal = Floki.find(html, ".modal.is-active")

      assert "3 charging sessions" =
               modal |> Floki.find(".modal-card-body strong") |> Floki.text()

      assert ["Continue", "Add costs retroactively"] =
               modal |> Floki.find(".modal-card-foot button") |> Enum.map(&Floki.text/1)
    end

    test "shows modal if a session fee was entered", %{conn: conn} do
      car = car_fixture()
      lat = 47.81444104508753
      lng = 12.367612123489382
      :ok = insert_charging_processes(car, {lat, lng})

      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      assert [] == html |> Floki.parse_document!() |> Floki.find(".modal.is-active")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "Supercharger",
            latitude: 47.814441,
            longitude: 12.367768,
            radius: 30,
            billing_type: :per_kwh,
            cost_per_unit: nil,
            session_fee: 4.69
          }
        })
        |> Floki.parse_document!()

      modal = Floki.find(html, ".modal.is-active")

      assert "3 charging sessions" =
               modal |> Floki.find(".modal-card-body strong") |> Floki.text()

      assert ["Continue", "Add costs retroactively"] =
               modal |> Floki.find(".modal-card-foot button") |> Enum.map(&Floki.text/1)
    end

    test "shows modal if the position changed", %{conn: conn} do
      car = car_fixture()

      %GeoFence{id: id} =
        geofence_fixture(%{
          name: "Supercharger",
          latitude: 47.814441,
          longitude: 12.367768,
          radius: 30,
          billing_type: :per_kwh,
          cost_per_unit: nil,
          session_fee: 4.69
        })

      :ok = insert_charging_processes(car, {47.81444104508753, 12.367612123489382})

      # Edit geofence

      assert {:ok, view, h} = live(conn, "/geo-fences/#{id}/edit")
      h = Floki.parse_document!(h)

      assert [] == Floki.find(h, ".modal.is-active")
      assert ["47.814441"] = h |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert ["12.367768"] = h |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{geo_fence: %{latitude: 47.814451, longitude: 12.367761}})
        |> Floki.parse_document!()

      modal = Floki.find(html, ".modal.is-active")

      assert "3 charging sessions" =
               modal |> Floki.find(".modal-card-body strong") |> Floki.text()

      assert ["Continue", "Add costs retroactively"] =
               modal |> Floki.find(".modal-card-foot button") |> Enum.map(&Floki.text/1)
    end

    test "shows modal if the radius changed", %{conn: conn} do
      car = car_fixture()

      %GeoFence{id: id} =
        geofence_fixture(%{
          name: "Supercharger",
          latitude: 47.814441,
          longitude: 12.367768,
          radius: 30,
          billing_type: :per_kwh,
          cost_per_unit: 0.42,
          session_fee: nil
        })

      :ok = insert_charging_processes(car, {47.81444104508753, 12.367612123489382})

      # Edit geofence

      assert {:ok, view, h} = live(conn, "/geo-fences/#{id}/edit")
      h = Floki.parse_document!(h)

      assert [] == Floki.find(h, ".modal.is-active")
      assert ["47.814441"] = h |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert ["12.367768"] = h |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{geo_fence: %{radius: 50}})
        |> Floki.parse_document!()

      modal = Floki.find(html, ".modal.is-active")

      assert "3 charging sessions" =
               modal |> Floki.find(".modal-card-body strong") |> Floki.text()

      assert ["Continue", "Add costs retroactively"] =
               modal |> Floki.find(".modal-card-foot button") |> Enum.map(&Floki.text/1)
    end

    test "adds charging costs", %{conn: conn} do
      car = car_fixture()
      :ok = insert_charging_processes(car, {47.81444104508753, 12.367612123489382})
      :ok = insert_charging_processes(car, {42.0, 69.0})

      assert {:ok, view, html} = live(conn, "/geo-fences/new")
      assert [] == html |> Floki.parse_document!() |> Floki.find(".modal.is-active")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "Supercharger",
            latitude: 47.814441,
            longitude: 12.367768,
            radius: 30,
            billing_type: :per_kwh,
            cost_per_unit: 0.33,
            session_fee: 5.00
          }
        })
        |> Floki.parse_document!()

      assert [
               {"button", [_, {"phx-click", "calc-costs"}, {"phx-value-result", "no"}],
                ["Continue"]},
               {"button", [_, {"phx-click", "calc-costs"}, {"phx-value-result", "yes"}],
                ["Add costs retroactively"]}
             ] = html |> Floki.find(".modal.is-active") |> Floki.find(".modal-card-foot button")

      view
      |> element(".modal button", "Add costs retroactively")
      |> render_click()

      assert_redirect(view, "/geo-fences")

      assert [
               %ChargingProcess{
                 geofence_id: id,
                 charge_energy_added: decimal(50.63),
                 charge_energy_used: nil,
                 cost: decimal("99.00")
               },
               %ChargingProcess{
                 geofence_id: id,
                 charge_energy_added: decimal(4.57),
                 charge_energy_used: nil,
                 cost: decimal(6.51)
               },
               %ChargingProcess{
                 geofence_id: id,
                 charge_energy_added: decimal(11.82),
                 charge_energy_used: nil,
                 cost: decimal("8.90")
               },
               %ChargingProcess{
                 geofence_id: id,
                 charge_energy_added: decimal("52.10"),
                 charge_energy_used: nil,
                 cost: decimal(22.19)
               },
               %ChargingProcess{geofence_id: nil, cost: decimal("99.00")},
               %ChargingProcess{geofence_id: nil, cost: nil},
               %ChargingProcess{geofence_id: nil, cost: nil},
               %ChargingProcess{geofence_id: nil, cost: nil}
             ] = Repo.all(from c in ChargingProcess, order_by: c.id)

      assert %GeoFence{
               name: "Supercharger",
               latitude: decimal(47.814441),
               longitude: decimal(12.367768),
               radius: 30,
               billing_type: :per_kwh,
               cost_per_unit: decimal("0.3300"),
               session_fee: decimal("5.00")
             } = Repo.get(GeoFence, id)
    end

    test "skips adding charging costs", %{conn: conn} do
      car = car_fixture()
      :ok = insert_charging_processes(car, {47.81444104508753, 12.367612123489382})

      assert {:ok, view, _html} = live(conn, "/geo-fences/new")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "Supercharger",
            latitude: 47.814441,
            longitude: 12.367768,
            radius: 30,
            billing_type: :per_kwh,
            cost_per_unit: 0.33,
            session_fee: 5.00
          }
        })
        |> Floki.parse_document!()

      assert [
               {"button", [_, {"phx-click", "calc-costs"}, {"phx-value-result", "no"}],
                ["Continue"]},
               {"button", [_, {"phx-click", "calc-costs"}, {"phx-value-result", "yes"}],
                ["Add costs retroactively"]}
             ] = html |> Floki.find(".modal.is-active") |> Floki.find(".modal-card-foot button")

      view
      |> element(".modal button", "Continue")
      |> render_click()

      assert_redirect(view, "/geo-fences")

      assert [
               %ChargingProcess{geofence_id: id, cost: decimal("99.00")},
               %ChargingProcess{geofence_id: id, cost: nil},
               %ChargingProcess{geofence_id: id, cost: nil},
               %ChargingProcess{geofence_id: id, cost: nil}
             ] = Repo.all(from c in ChargingProcess, order_by: c.id)

      assert %GeoFence{
               name: "Supercharger",
               latitude: decimal(47.814441),
               longitude: decimal(12.367768),
               radius: 30,
               billing_type: :per_kwh,
               cost_per_unit: decimal("0.3300"),
               session_fee: decimal("5.00")
             } = Repo.get(GeoFence, id)
    end

    defp insert_charging_processes(car, {lat, lng}) do
      {:ok, %Position{id: position_id}} =
        Log.insert_position(car, %{date: DateTime.utc_now(), latitude: lat, longitude: lng})

      data =
        for {sir, eir, srr, err, ca, sl, el, d, c} <- [
              {80.5, 412.4, nil, nil, 50.63, 16, 83, 70, 99.0},
              {109.7, 139.7, 108.7, 139.7, 4.57, 22, 28, 26, nil},
              {63.9, 142.3, 64.9, 142.3, 11.82, 13, 29, 221, nil},
              {107.9, 450.1, 108.9, 450.1, 52.1, 22, 90, 40, nil}
            ] do
          %{
            car_id: car.id,
            start_date: DateTime.utc_now(),
            position_id: position_id,
            start_ideal_range_km: sir,
            end_ideal_range_km: eir,
            start_rated_range_km: srr,
            end_rated_range_km: err,
            charge_energy_added: ca,
            start_battery_level: sl,
            end_battery_level: el,
            duration_min: d,
            cost: c
          }
        end

      {_, nil} = Repo.insert_all(ChargingProcess, data)

      :ok
    end
  end
end
