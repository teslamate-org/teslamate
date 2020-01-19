defmodule TeslaMateWeb.ChargeLive.CostTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.Log.ChargingProcess
  alias TeslaMate.Log.Car
  alias TeslaMate.{Log, Locations, Repo}

  describe "metadata" do
    test "hides the date if the charge has no end_date", %{conn: conn} do
      car = car_fixture()

      # incomplete

      {:ok, %ChargingProcess{id: id} = cp} =
        Log.start_charging_process(car, %{date: DateTime.utc_now(), latitude: 0, longitude: 0})

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")
      assert [] == Floki.find(html, "#date-tag")

      # complete

      assert {:ok, %ChargingProcess{start_date: start_date, end_date: end_date}} =
               Log.complete_charging_process(cp)

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [tag] = Floki.find(html, "#date-tag")

      assert tag
             |> Floki.find("[data-start-date]")
             |> Floki.attribute("data-start-date") == [DateTime.to_iso8601(start_date)]

      assert tag
             |> Floki.find("[data-end-date]")
             |> Floki.attribute("data-end-date") == [DateTime.to_iso8601(end_date)]
    end

    test "shows either charge_energy_used or charge_energy_added", %{conn: conn} do
      cases = [
        {%{charge_energy_used: 50.0, charge_energy_added: 48.1}, "50.0 kWh"},
        {%{charge_energy_used: 50.0, charge_energy_added: 50.5}, "50.5 kWh"},
        {%{charge_energy_used: nil, charge_energy_added: 50.0}, "50.0 kWh"}
      ]

      for {attrs, tag_str} <- cases do
        rnd = :rand.uniform(65536)
        car = car_fixture(eid: rnd, vid: rnd, vin: to_string(rnd))
        %ChargingProcess{id: id} = charging_process_fixture(car, attrs)

        assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

        assert [
                 {"div", _,
                  [
                    {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-flash"}], _}]}]},
                    {"span", _, [^tag_str]}
                  ]}
               ] = Floki.find(html, "#energy-tag")
      end

      # both nil

      attrs = %{charge_energy_used: nil, charge_energy_added: nil}
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(), attrs)
      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")
      assert [] = Floki.find(html, "#energy-tag")
    end

    test "shows the car name", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(name: "joe"))
      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-car"}], _}]}]},
                  {"span", _, ["joe"]}
                ]}
             ] = Floki.find(html, "#car-tag")
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

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-map-marker"}], _}]}]},
                  {"span", _, ["Post Office"]}
                ]}
             ] = Floki.find(html, "#location-tag")
    end

    test "shows the address name", %{conn: conn} do
      {:ok, address} =
        Locations.create_address(%{
          display_name:
            "Beelitz Supercharger, Dr.-Herrmann-Straße, Beelitz-Heilstätten, Beelitz, Potsdam-Mittelmark, Brandenburg, 14547, Deutschland",
          place_id: 66_385_359,
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

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")

      assert [
               {"div", _,
                [
                  {"span", _, [{"span", _, [{"span", [{"class", "mdi mdi-map-marker"}], _}]}]},
                  {"span", _, ["Beelitz Supercharger, Beelitz"]}
                ]}
             ] = Floki.find(html, "#location-tag")
    end
  end

  describe "editing" do
    test "saves the charge cost", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture(), %{cost: nil})

      assert {:ok, view, html} = live(conn, "/charge-cost/#{id}")
      assert [] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")

      html = render_submit(view, :save, %{charging_process: %{cost: 42.12}})
      assert ["42.12"] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert Decimal.from_float(42.12) == Repo.get(ChargingProcess, id).cost

      html = render_submit(view, :save, %{charging_process: %{cost: nil}})
      assert [] = html |> Floki.find("#charging_process_cost") |> Floki.attribute("value")
      assert nil == Repo.get(ChargingProcess, id).cost
    end
  end

  describe "back button" do
    test "redirects to the original referrer", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture())

      assert {:ok, _view, html} =
               live(conn, "/charge-cost/#{id}",
                 connect_params: %{"referrer" => "http://grafana.example.com/d/xyz/12"}
               )

      assert ["http://grafana.example.com/d/xyz/12"] =
               html
               |> Floki.find(".control a")
               |> Floki.attribute("href")
    end

    test "redirects to home page if there is no referrer", %{conn: conn} do
      %ChargingProcess{id: id} = charging_process_fixture(car_fixture())

      assert {:ok, _view, html} =
               live(conn, "/charge-cost/#{id}", connect_params: %{"referrer" => nil})

      assert ["/"] =
               html
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
