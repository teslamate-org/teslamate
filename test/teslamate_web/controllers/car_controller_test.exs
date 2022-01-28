defmodule TeslaMateWeb.CarControllerTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.{Log, Settings, Repo}
  alias TeslaMate.Log.Car

  defp table_row(html, key, value, opts \\ []) do
    assert {"tr", _, [{"td", _, [^key]}, {"td", [], [v]}]} =
             html
             |> Floki.parse_document!()
             |> Floki.find("tr")
             |> Enum.find(&match?({"tr", _, [{"td", _, [^key]}, _td]}, &1))

    case Keyword.get(opts, :tooltip) do
      nil -> assert value == v
      str -> assert {"span", [_, {"data-tooltip", ^str}], [^value]} = v
    end
  end

  defp icon(html, tooltip, icon) do
    icon_class = "mdi mdi-#{icon}"

    assert {"span", _, [{"span", [{"class", ^icon_class}], _}]} =
             html
             |> Floki.parse_document!()
             |> Floki.find(".icons .icon")
             |> Enum.find(&match?({"span", [_, {"data-tooltip", ^tooltip}], _}, &1))
  end

  defp car_fixture(settings) do
    {:ok, car} =
      Log.create_car(%{
        efficiency: 0.153,
        eid: 4242,
        vid: 404,
        vin: "xxxxx",
        model: "S",
        name: "foo",
        trim_badging: "P100D"
      })

    {:ok, _settings} =
      car.settings
      |> Repo.preload(:car)
      |> Settings.update_car_settings(settings)

    car
  end

  describe "index" do
    test "redirects if not signed in", %{conn: conn} do
      assert conn = get(conn, Routes.car_path(conn, :index))
      assert redirected_to(conn, 302) == Routes.live_path(conn, TeslaMateWeb.SignInLive.Index)
    end

    @tag :signed_in
    test "lists all active vehicles", %{conn: conn} do
      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event()}], pid: self()}
        )

      {:ok, _pid} =
        start_supervised(
          {TeslaMate.Vehicles,
           vehicle: VehicleMock,
           vehicles: [
             %TeslaApi.Vehicle{display_name: "f0o", id: 4241, vehicle_id: 11111, vin: "1221"},
             %TeslaApi.Vehicle{display_name: "fo0", id: 1242, vehicle_id: 22222, vin: "2112"}
           ]}
        )

      conn = get(conn, Routes.car_path(conn, :index))
      html = response(conn, 200)

      assert [
               {"div", [{"class", "car card"}], _},
               {"div", [{"class", "car card"}], _}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find(".car")
    end

    @tag :signed_in
    test "renders last knwon vehicle stats", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep", display_name: "FooCar"}}
      ]

      {:ok, car} =
        %Car{settings: %CarSettings{}}
        |> Car.changeset(%{vid: 404, eid: 404, vin: "xxxxx"})
        |> Log.create_or_update_car()

      {:ok, _position} =
        Log.insert_position(car, %{
          date: DateTime.utc_now(),
          longitude: 0,
          latitude: 0,
          rated_battery_range_km: 380.25,
          est_battery_range_km: 401.52,
          ideal_battery_range_km: 175.1,
          battery_level: 80,
          outside_temp: 20.1,
          inside_temp: 21.0
        })

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "asleep")
      assert table_row(html, "Range (rated)", "380.26 km")
      assert table_row(html, "Range (est.)", "401.52 km")
      assert table_row(html, "State of Charge", "80%", tooltip: "≈ 475 km at 100%")
      assert table_row(html, "Outside Temperature", "20.1 °C")
      assert table_row(html, "Inside Temperature", "21.0 °C")
    end

    @tag :signed_in
    test "displays the friendly name", %{conn: conn} do
      now = (DateTime.utc_now() |> DateTime.to_unix()) * 1000

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: now, latitude: 0.0, longitude: 0.0},
           vehicle_config: %{car_type: "model3", trim_badging: "p74d"}
         )}
      ]

      :ok = start_vehicles(events)

      Process.sleep(250)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)

      assert "Model 3 LR AWD Performance" ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".car .subtitle")
               |> Floki.text()
    end

    @tag :signed_in
    test "renders current vehicle stats [:online]", %{conn: conn} do
      now = (DateTime.utc_now() |> DateTime.to_unix()) * 1000

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: now, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             battery_range: 200,
             est_battery_range: 180,
             ideal_battery_range: 175,
             usable_battery_level: 67,
             battery_level: 69
           },
           climate_state: %{is_preconditioning: true, outside_temp: 24, inside_temp: 23.2},
           vehicle_state: %{
             timestamp: 0,
             car_version: "2019.40.50.7 ad132c7b057e",
             software_update: %{status: "available", version: "2020.4.1 4a4ad401858f"},
             locked: true,
             sentry_mode: true,
             fd_window: 1,
             fp_window: 0,
             rd_window: 0,
             rp_window: 0,
             df: 0,
             dr: 0,
             pf: 1,
             pr: 0,
             is_user_present: true,
             odometer: 26097.59
           },
           vehicle_config: %{car_type: "models2", trim_badging: "p90d"}
         )}
      ]

      :ok = start_vehicles(events)

      Process.sleep(250)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/

      assert "Model S P90D" ==
               html
               |> Floki.parse_document!()
               |> Floki.find(".car .subtitle")
               |> Floki.text()

      assert table_row(html, "Status", "online")
      assert table_row(html, "Range (rated)", "321.87 km")
      assert table_row(html, "Range (est.)", "289.68 km")
      assert table_row(html, "State of Charge", "67% (69%)", tooltip: "≈ 480 km at 100%")
      assert icon(html, "Locked", "lock")
      assert icon(html, "Driver present", "account")
      assert icon(html, "Preconditioning", "air-conditioner")
      assert icon(html, "Sentry Mode", "shield-check")
      assert icon(html, "Windows open", "window-open")
      assert icon(html, "Doors open", "car-door")
      assert icon(html, "Software Update available (2020.4.1)", "gift-outline")
      assert table_row(html, "Outside Temperature", "24 °C")
      assert table_row(html, "Inside Temperature", "23.2 °C")
      assert table_row(html, "Mileage", "42000 km")

      assert table_row(
               html,
               "Version",
               {"a",
                [
                  {"href",
                   "https://www.notateslaapp.com/software-updates/version/2019.40.50.7/release-notes"},
                  {"rel", "noopener noreferrer"},
                  {"target", "_blank"}
                ], ["2019.40.50.7"]}
             )
    end

    @tag :signed_in
    test "renders current vehicle stats [:charging]", %{conn: conn} do
      car = car_fixture(%{})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             timestamp: 0,
             charger_power: 11,
             charger_phases: 3,
             charger_voltage: 229,
             charger_actual_current: 16,
             battery_range: 200,
             est_battery_range: 180,
             ideal_battery_range: 175,
             charging_state: "Charging",
             charge_energy_added: "4.32",
             charge_port_latch: "Engaged",
             charge_port_door_open: true,
             charge_port_cold_weather_mode: false,
             scheduled_charging_start_time: 1_565_620_707,
             charge_limit_soc: 85,
             time_to_full_charge: 1.83
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "charging")
      assert table_row(html, "Remaining Time", "1 h, 49 min")
      assert icon(html, "Plugged In", "power-plug")
      assert table_row(html, "Range (rated)", "321.87 km")
      assert table_row(html, "Range (est.)", "289.68 km")
      assert table_row(html, "Charged", "4.32 kWh")
      assert table_row(html, "Charger Power", "11 kW")

      assert table_row(
               html,
               "Scheduled Charging",
               {"span",
                [
                  {"data-date", "2019-08-12T14:38:27Z"},
                  {"id", "scheduled_start_time_#{car.id}"},
                  {"phx-hook", "LocalTime"}
                ], []}
             )

      assert table_row(html, "Charge Limit", "85%")
    end

    @tag :signed_in
    test "does not render remaining seconds", %{conn: conn} do
      events = [
        {:ok,
         online_event(
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             timestamp: 0,
             charging_state: "Charging",
             charge_energy_added: "4.32",
             ideal_battery_range: 200,
             time_to_full_charge: 0.33
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert table_row(html, "Remaining Time", "19 min")
    end

    @tag :signed_in
    test "renders current vehicle stats [:driving]", %{conn: conn} do
      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{
             timestamp: 0,
             latitude: 0.0,
             longitude: 0.0,
             shift_state: "D",
             speed: 30
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "driving")
      assert table_row(html, "Speed", "48 km/h")
    end

    @tag :signed_in
    test "renders current vehicle stats [:updating]", %{conn: conn} do
      alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           vehicle_state: %{
             timestamp: 0,
             car_version: "2019.8.4 530d1d3",
             software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: "installing"}
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "updating")
    end

    @tag :signed_in
    test "renders current vehicle stats [:asleep]", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{display_name: "FooCar", state: "asleep"}}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "asleep")
    end

    @tag :signed_in
    test "renders current vehicle stats [:offline]", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{display_name: "FooCar", state: "offline"}}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "offline")
    end

    @tag :signed_in
    test "renders current vehicle stats [:falling asleep]", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 1, use_streaming_api: false})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)

      Process.sleep(100)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "falling asleep")
    end

    @tag :capture_log
    @tag :signed_in
    test "renders current vehicle stats [:unavailable]", %{conn: conn} do
      events = [
        {:error, :unknown}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5"><\/p>/
      assert table_row(html, "Status", "unavailable")
    end

    @tag :signed_in
    test "displays the rated range if preferred", %{conn: conn} do
      {:ok, _} =
        Settings.get_global_settings!()
        |> Settings.update_global_settings(%{preferred_range: :rated})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             ideal_battery_range: 200,
             est_battery_range: 180,
             battery_range: 175,
             battery_level: 69
           },
           climate_state: %{is_preconditioning: false, outside_temp: 24, inside_temp: 23.2},
           vehicle_state: %{timestamp: 0, locked: true, sentry_mode: true, car_version: ""},
           vehicle_config: %{car_type: "models2", trim_badging: "p90d"}
         )}
      ]

      :ok = start_vehicles(events)

      Process.sleep(250)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Range (rated)", "281.64 km")
      assert table_row(html, "Range (est.)", "289.68 km")
    end

    @tag :signed_in
    @tag :capture_log
    test "displays imperial units", %{conn: conn} do
      {:ok, _} =
        Settings.get_global_settings!()
        |> Settings.update_global_settings(%{unit_of_length: :mi, unit_of_temperature: :F})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{
             timestamp: 0,
             latitude: 0.0,
             longitude: 0.0,
             shift_state: "D",
             speed: 30
           },
           charge_state: %{
             battery_range: 200,
             est_battery_range: 180,
             ideal_battery_range: 175,
             usable_battery_level: 67,
             battery_level: 69
           },
           climate_state: %{
             is_preconditioning: false,
             outside_temp: 24,
             inside_temp: 23.2
           },
           vehicle_state: %{
             odometer: 42000
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-5">FooCar<\/p>/
      assert table_row(html, "Status", "driving")
      assert table_row(html, "Range (rated)", "200.0 mi")
      assert table_row(html, "Range (est.)", "180.0 mi")
      assert table_row(html, "State of Charge", "67% (69%)", tooltip: "≈ 299 mi at 100%")
      assert table_row(html, "Speed", "30 mph")
      assert table_row(html, "Outside Temperature", "75.2 °F")
      assert table_row(html, "Inside Temperature", "73.8 °F")
      assert table_row(html, "Mileage", "42000 mi")
    end
  end

  describe "supsend" do
    setup %{conn: conn} do
      {:ok, conn: put_req_header(conn, "accept", "application/json")}
    end

    test "suspends logging", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 60, use_streaming_api: false})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)

      %Car{id: id} = Log.get_car_by(vin: "xxxxx")

      conn = put(conn, Routes.car_path(conn, :suspend_logging, id))

      assert "" == response(conn, 204)
    end

    test "returns error if suspending is not possible", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 60, use_streaming_api: false})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: true}
         )}
      ]

      :ok = start_vehicles(events)

      %Car{id: id} = Log.get_car_by(vin: "xxxxx")

      conn = put(conn, Routes.car_path(conn, :suspend_logging, id))
      assert "preconditioning" == json_response(conn, 412)["error"]
    end
  end

  describe "resume" do
    test "resumes logging", %{conn: conn} do
      alias TeslaMate.Vehicles.Vehicle.Summary

      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 1, use_streaming_api: false})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)
      Process.sleep(100)

      %Car{id: id} = Log.get_car_by(vin: "xxxxx")
      assert %Summary{state: :suspended} = TeslaMate.Vehicles.summary(id)

      conn = put(conn, Routes.car_path(conn, :resume_logging, id))
      assert "" == response(conn, 204)
    end
  end

  def start_vehicles(events \\ []) do
    {:ok, _pid} = start_supervised({ApiMock, name: :api_vehicle, events: events, pid: self()})

    {:ok, _pid} =
      start_supervised(
        {TeslaMate.Vehicles,
         vehicle: VehicleMock,
         vehicles: [
           %TeslaApi.Vehicle{
             display_name: "foo",
             id: 4242,
             vehicle_id: 404,
             vin: "xxxxx"
           }
         ]}
      )

    :ok
  end
end
