defmodule TeslaMateWeb.ChargeLive.CostTest do
  use TeslaMateWeb.ConnCase, async: false
  use TeslaMate.VehicleCase, async: false

  alias TeslaMate.Log.ChargingProcess
  alias TeslaMate.{Log, Locations, Repo}

  import TestHelper, only: [decimal: 1]

  describe "metadata" do
    test "hides the date if the charge has no end_date", %{conn: conn} do
      car = car_fixture()

      # incomplete

      {:ok, %ChargingProcess{id: id} = cp} =
        Log.start_charging_process(car, %{date: DateTime.utc_now(), latitude: 0, longitude: 0})

      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [] ==
               html
               |> Floki.parse_document!()
               |> Floki.find("#date-tag")

      # complete

      assert {:ok, %ChargingProcess{start_date: start_date, end_date: end_date}} =
               Log.complete_charging_process(cp)

      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [tag] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#date-tag")

      assert tag
             |> Floki.find("[data-start-date]")
             |> Floki.attribute("data-start-date") == [DateTime.to_iso8601(start_date)]

      assert tag
             |> Floki.find("[data-end-date]")
             |> Floki.attribute("data-end-date") == [DateTime.to_iso8601(end_date)]
    end

    test "shows the duration in minutes", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(), %{duration_min: 30})
      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-clock"}], _}]}]},
                  {"span", _, ["30 min"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#duration-tag")
    end

    test "shows either charge_energy_used or charge_energy_added", %{conn: conn} do
      cases = [
        {%{charge_energy_used: 50.0, charge_energy_added: 48.1}, "50.00 kWh"},
        {%{charge_energy_used: 50.0, charge_energy_added: 50.5}, "50.50 kWh"},
        {%{charge_energy_used: nil, charge_energy_added: 50.0}, "50.00 kWh"}
      ]

      for {attrs, tag_str} <- cases do
        rnd = :rand.uniform(65536)
        car = car_fixture(eid: rnd, vid: rnd, vin: to_string(rnd))
        %ChargingProcess{id: id} = charging_process_fixture(car, attrs)

        assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

        assert [
                 {"div", _,
                  [
                    {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-flash"}], _}]}]},
                    {"span", _, [^tag_str]}
                  ]}
               ] =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find("#energy-tag")
      end

      # both nil

      attrs = %{charge_energy_used: nil, charge_energy_added: nil}
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(), attrs)
      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#energy-tag")
    end

    test "shows the car name", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(name: "joe"))
      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-car"}], _}]}]},
                  {"span", _, ["joe"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#car-tag")
    end

    test "shows the geo-fence name", %{conn: conn} do
      {:ok, geofence} =
        Locations.create_geofence(%{
          name: "Post Office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 100
        })

      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{geofence_id: geofence.id})

      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-map-marker"}], _}]}]},
                  {"span", _, ["Post Office"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#location-tag")
    end

    test "shows the address name", %{conn: conn} do
      {:ok, address} =
        Locations.create_address(%{
          display_name:
            "Beelitz Supercharger, Dr.-Herrmann-Straße, Beelitz-Heilstätten, Beelitz, Potsdam-Mittelmark, Brandenburg, 14547, Deutschland",
          osm_id: 66_385_359,
          osm_type: "way",
          latitude: 52.2668097,
          longitude: 12.9223251,
          name: "Beelitz Supercharger",
          house_number: nil,
          road: "Dr.-Herrmann-Straße",
          neighbourhood: "Beelitz-Heilstätten",
          city: "Beelitz",
          county: "Potsdam-Mittelmark",
          postcode: "14547",
          state: "Brandenburg",
          state_district: nil,
          country: "Deutschland",
          raw: %{}
        })

      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{address_id: address.id})

      assert {:ok, _view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-map-marker"}], _}]}]},
                  {"span", _, ["Beelitz Supercharger, Beelitz"]}
                ]}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#location-tag")
    end
  end

  describe "editing" do
    test "saves the charge cost", %{conn: conn} do
      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{
          cost: nil,
          charge_energy_added: 8,
          charge_energy_used: 10
        })

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#charging_process_cost")
               |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{charging_process: %{cost: 42.12}})
        |> Floki.parse_document!()

      assert "Total" =
               html |> Floki.find("#charging_process_mode option[selected]") |> Floki.text()

      assert ["42.12"] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert %ChargingProcess{cost: decimal("42.12")} = Repo.get(ChargingProcess, id)

      html =
        render_submit(view, :save, %{charging_process: %{cost: nil}})
        |> Floki.parse_document!()

      assert [] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert nil == Repo.get(ChargingProcess, id).cost
    end

    test "allows to enter the cost per kWh", %{conn: conn} do
      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{
          cost: nil,
          charge_energy_added: 8,
          charge_energy_used: 10
        })

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#charging_process_cost")
               |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{charging_process: %{cost: 0.12, mode: "per_kwh"}})
        |> Floki.parse_document!()

      assert "Total" =
               html |> Floki.find("#charging_process_mode option[selected]") |> Floki.text()

      assert ["1.20"] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert %ChargingProcess{cost: decimal("1.20")} = Repo.get(ChargingProcess, id)

      html =
        render_submit(view, :save, %{charging_process: %{cost: nil}})
        |> Floki.parse_document!()

      assert [] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert nil == Repo.get(ChargingProcess, id).cost
    end

    test "allows negative charge cost", %{conn: conn} do
      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{
          cost: nil,
          charge_energy_added: 8,
          charge_energy_used: 10
        })

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#charging_process_cost")
               |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{charging_process: %{cost: -0.029, mode: "per_kwh"}})
        |> Floki.parse_document!()

      assert "Total" =
               html |> Floki.find("#charging_process_mode option[selected]") |> Floki.text()

      assert ["-0.29"] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert %ChargingProcess{cost: decimal("-0.29")} = Repo.get(ChargingProcess, id)

      html =
        render_submit(view, :save, %{charging_process: %{cost: nil}})
        |> Floki.parse_document!()

      assert [] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert nil == Repo.get(ChargingProcess, id).cost
    end

    test "allows to enter the cost per Minute", %{conn: conn} do
      %ChargingProcess{id: id} =
        charging_process_fixture(car_fixture(), %{
          cost: nil,
          charge_energy_added: 8,
          charge_energy_used: 10,
          duration_min: 15
        })

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("#charging_process_cost")
               |> Floki.attribute("value")

      html =
        render_submit(view, :save, %{charging_process: %{cost: 0.10, mode: "per_minute"}})
        |> Floki.parse_document!()

      assert "Total" =
               html |> Floki.find("#charging_process_mode option[selected]") |> Floki.text()

      assert ["1.50"] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert %ChargingProcess{cost: decimal("1.50")} = Repo.get(ChargingProcess, id)
    end
  end

  describe "back button" do
    test "redirects to the original referrer", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture())

      assert {:ok, _view, html} =
               conn
               |> put_connect_params(%{"referrer" => "http://grafana.example.com/d/xyz/12"})
               |> live("/charge-cost/#{id}")

      assert ["http://grafana.example.com/d/xyz/12"] =
               html
               |> Floki.parse_document!()
               |> Floki.find(".control a")
               |> Floki.attribute("href")
    end

    test "redirects to home page if there is no referrer", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture())

      assert {:ok, _view, html} =
               conn
               |> put_connect_params(%{"referrer" => nil})
               |> live("/charge-cost/#{id}")

      assert ["/"] =
               html
               |> Floki.parse_document!()
               |> Floki.find(".control a")
               |> Floki.attribute("href")
    end
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{
        efficiency: 0.153,
        eid: 42,
        model: "s",
        vid: 42,
        name: "foo",
        trim_badging: "p100d",
        vin: "12345f"
      })
      |> Log.create_car()

    car
  end

  defp charging_process_fixture(car, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        start_date: DateTime.utc_now(),
        position: %{date: DateTime.utc_now(), latitude: 0, longitude: 0, car_id: car.id}
      })

    {:ok, charging_process} =
      %ChargingProcess{car_id: car.id}
      |> ChargingProcess.changeset(attrs)
      |> Repo.insert()

    charging_process
  end
end
