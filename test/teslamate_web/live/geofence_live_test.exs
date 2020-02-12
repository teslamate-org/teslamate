defmodule TeslaMateWeb.GeoFenceLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Locations, Settings, Log, Repo}
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.Car

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

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert [
               _,
               ["Victory Column", "52.51452, 13.35014", "100 m", _],
               ["Service Center", "52.39425, 13.54255", "100 m", _],
               ["Post office", "-25.06619, -130.1005", "100 m", _]
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

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["Post office", "-25.06619, -130.1005", "328 ft", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end

    test "allows deletion of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Victory Column", latitude: 52.514521, longitude: 13.350144})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["Victory Column", "52.51452, 13.35014", "100 m", _] =
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
      assert ["100.0"] = Floki.attribute(radius, "value")

      html =
        render_submit(view, :save, %{geo_fence: %{name: "", radius: ""}})
        |> Floki.parse_document!()

      assert [""] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")

      for id <- ["name", "radius"] do
        error_html =
          html
          |> Floki.find(".field-body .field")
          |> Enum.filter(fn field -> Floki.find(field, "#geo_fence_#{id}") |> length() == 1 end)
          |> Floki.find("span")
          |> Floki.raw_html(encode: false)

        assert error_html == "<span class=\"help is-danger pl-15\">can't be blank</span>"
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
      assert ["100.0"] = Floki.attribute(radius, "value")

      render_submit(view, :save, %{
        geo_fence: %{name: "Adamstown", longitude: 0, latitude: 0, radius: 20}
      })

      assert_redirect(view, "/geo-fences")

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["Adamstown", "0.0, 0.0", "20 m", _] =
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

      assert {:ok, view, html} = live(conn, "/geo-fences/new")
      html = Floki.parse_document!(html)

      latitude = Floki.find(html, "#geo_fence_latitude")
      longitude = Floki.find(html, "#geo_fence_longitude")

      assert ["48.067612"] = Floki.attribute(latitude, "value")
      assert ["12.862226"] = Floki.attribute(longitude, "value")
    end

    test "validates cahnges when creating a new geo-fence", %{conn: conn} do
      %Car{id: car_id} = car_fixture()

      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "",
            longitude: nil,
            latitude: nil,
            radius: "",
            cost_per_kwh: "wat"
          }
        })
        |> Floki.parse_document!()

      assert [""] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")
      assert [""] = html |> Floki.find("#geo_fence_radius") |> Floki.attribute("value")
      assert ["wat"] = html |> Floki.find("#geo_fence_cost_per_kwh") |> Floki.attribute("value")

      assert [
               field_position,
               field_name,
               field_cost_per_kwh,
               field_sleep_mode,
               _
             ] = Floki.find(html, ".field.is-horizontal")

      assert ["can't be blank", "can't be blank", "can't be blank"] =
               field_position |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert ["can't be blank"] = field_name |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert "is invalid" =
               field_cost_per_kwh
               |> Floki.find("span")
               |> Floki.text()

      assert ["checked"] =
               field_sleep_mode
               |> Floki.find("#sleep_mode_#{car_id}")
               |> Floki.attribute("checked")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "foo",
            longitude: "wot",
            latitude: "wat",
            radius: "40",
            cost_per_kwh: 0.25
          }
        })
        |> Floki.parse_document!()

      assert ["foo"] = html |> Floki.find("#geo_fence_name") |> Floki.attribute("value")
      assert ["wat"] = html |> Floki.find("#geo_fence_latitude") |> Floki.attribute("value")
      assert ["wot"] = html |> Floki.find("#geo_fence_longitude") |> Floki.attribute("value")
      assert ["40.0"] = html |> Floki.find("#geo_fence_radius") |> Floki.attribute("value")
      assert ["0.25"] = html |> Floki.find("#geo_fence_cost_per_kwh") |> Floki.attribute("value")

      assert [
               field_position,
               field_name,
               field_cost_per_kwh,
               _field_sleep_mode,
               _
             ] = Floki.find(html, ".field.is-horizontal")

      assert ["is invalid", "is invalid"] =
               field_position |> Floki.find("span") |> Enum.map(&Floki.text/1)

      assert [] =
               field_name
               |> Floki.find("span")
               |> Enum.map(&Floki.text/1)

      assert "" =
               field_cost_per_kwh
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

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.06619, -130.1005", "25 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end

    test "allows creating of a geo-fence with radius being displayed in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_global_settings!() |> Settings.update_global_settings(%{unit_of_length: :mi})

      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      render_submit(view, :save, %{
        geo_fence: %{
          name: "post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 15.2
        }
      })

      assert_redirect(view, "/geo-fences")

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.06619, -130.1005", "50 ft", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)

      {:ok, _settings} =
        Settings.get_global_settings!() |> Settings.update_global_settings(%{unit_of_length: :km})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert ["post office", "-25.06619, -130.1005", "15 m", _] =
               html |> Floki.parse_document!() |> Floki.find("td") |> Enum.map(&Floki.text/1)
    end
  end

  test "toggles sleep mode status", %{conn: conn} do
    %Car{id: car_id} = car = car_fixture()
    %Car{id: another_car_id} = another_car = car_fixture(vid: 43, eid: 43, vin: "43")

    {:ok, _settings} =
      Settings.get_car_settings!(another_car)
      |> Settings.update_car_settings(%{sleep_mode_enabled: false})

    assert {:ok, view, html} = live(conn, "/geo-fences/new")

    assert ["checked"] =
             html
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{car.id}")
             |> Floki.attribute("checked")

    assert [] =
             html
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{another_car.id}")
             |> Floki.attribute("checked")

    assert [] =
             render_click(view, :toggle, %{checked: "false", car: to_string(car.id)})
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{car.id}")
             |> Floki.attribute("checked")

    assert ["checked"] =
             render_click(view, :toggle, %{checked: "true", car: to_string(another_car.id)})
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{another_car.id}")
             |> Floki.attribute("checked")

    render_submit(view, :save, %{
      geo_fence: %{
        name: "post office",
        latitude: -25.066188,
        longitude: -130.100502,
        radius: 25
      }
    })

    assert_redirect(view, "/geo-fences")

    assert [
             %GeoFence{
               id: id,
               sleep_mode_blacklist: [%Car{id: ^car_id}],
               sleep_mode_whitelist: [%Car{id: ^another_car_id}]
             }
           ] =
             Locations.list_geofences()
             |> Enum.map(&Repo.preload(&1, [:sleep_mode_blacklist, :sleep_mode_whitelist]))

    # enable sleep mode(s)

    assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")

    assert [] =
             html
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{car.id}")
             |> Floki.attribute("checked")

    assert ["checked"] =
             html
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{another_car.id}")
             |> Floki.attribute("checked")

    assert ["checked"] =
             render_click(view, :toggle, %{checked: "true", car: to_string(car.id)})
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{car.id}")
             |> Floki.attribute("checked")

    assert [] =
             render_click(view, :toggle, %{checked: "false", car: to_string(another_car.id)})
             |> Floki.parse_document!()
             |> Floki.find("#sleep_mode_#{another_car.id}")
             |> Floki.attribute("checked")

    render_submit(view, :save, %{geo_fence: %{name: "post_office", radius: 20}})
    assert_redirect(view, "/geo-fences")

    assert [
             %GeoFence{
               id: ^id,
               sleep_mode_blacklist: [],
               sleep_mode_whitelist: []
             }
           ] =
             Locations.list_geofences()
             |> Enum.map(&Repo.preload(&1, [:sleep_mode_blacklist, :sleep_mode_whitelist]))
  end

  describe "grafana URL" do
    alias TeslaMate.Settings.GlobalSettings

    test "initiall sets the base URL", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      assert {:ok, _parent_view, _html} =
               live(conn, "/geo-fences/new?lat=0.0&lng=0.0",
                 connect_params: %{"referrer" => "http://grafana.example.com/d/xyz/12"}
               )

      assert %GlobalSettings{grafana_url: "http://grafana.example.com"} =
               Settings.get_global_settings!()
    end

    test "handles weird referrers", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      for referrer <- [nil, "", "example.com", "http://example.com", "http://example.com/"] do
        assert {:ok, _parent_view, _html} =
                 live(conn, "/geo-fences/new?lat=0.0&lng=0.0",
                   connect_params: %{"referrer" => referrer}
                 )

        assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()
      end
    end

    test "keeps the path", %{conn: conn} do
      assert %GlobalSettings{grafana_url: nil} = Settings.get_global_settings!()

      assert {:ok, _parent_view, _html} =
               live(conn, "/geo-fences/new?lat=0.0&lng=0.0",
                 connect_params: %{"referrer" => "http://example.com:9090/grafana/d/xyz/12"}
               )

      assert %GlobalSettings{grafana_url: "http://example.com:9090/grafana"} =
               Settings.get_global_settings!()
    end

    test "does not update the base URL if exists already", %{conn: conn} do
      assert {:ok, _settings} =
               Settings.get_global_settings!()
               |> Settings.update_global_settings(%{grafana_url: "https://grafana.example.com"})

      assert {:ok, _parent_view, _html} =
               live(conn, "/geo-fences/new?lat=0.0&lng=0.0",
                 connect_params: %{"referrer" => "http://grafana.foo.com/d/xyz/12"}
               )

      assert %GlobalSettings{grafana_url: "https://grafana.example.com"} =
               Settings.get_global_settings!()
    end
  end
end
