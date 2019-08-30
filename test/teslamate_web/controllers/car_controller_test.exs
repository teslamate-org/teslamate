defmodule TeslaMateWeb.CarControllerTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.{Log, Settings}
  alias TeslaMate.Log.Car

  defp table_row(key, value) do
    ~r/<tr>\n?\s*<td>#{key}<\/td>\n?\s*<td.*?>\n?\s*#{value}\n?\s*<\/td>\n?\s*<\/tr>/
  end

  describe "index" do
    test "redirects if not signed in", %{conn: conn} do
      assert conn = get(conn, Routes.car_path(conn, :index))
      assert redirected_to(conn, 302) == Routes.live_path(conn, TeslaMateWeb.SignInLive.Index)
    end

    # @tag :signed_in
    # test "lists all cares", %{conn: conn} do
    # end

    @tag :signed_in
    test "renders last knwon vehicle stats", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep", display_name: "FooCar"}}
      ]

      :ok = start_vehicles(events)

      %Car{id: id} = Log.get_car_by_eid(4242)

      {:ok, _position} =
        Log.insert_position(id, %{
          date: DateTime.utc_now(),
          longitude: 0,
          latitude: 0,
          ideal_battery_range_km: 380.1,
          est_battery_range_km: 401.5,
          battery_range_km: 175.1,
          battery_level: 80,
          outside_temp: 20.1,
          inside_temp: 21.0
        })

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "asleep")
      assert html =~ table_row("Range \\(typical\\)", "380.1 km")
      assert html =~ table_row("Range \\(est.\\)", "401.5 km")
      assert html =~ table_row("Range \\(rated\\)", "175.1 km")
      assert html =~ table_row("State of Charge", "80%")
      assert html =~ table_row("Outside temperature", "20.1 °C")
      assert html =~ table_row("Inside temperature", "21.0 °C")
    end

    @tag :signed_in
    test "renders current vehicle stats [:online]", %{conn: conn} do
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
           vehicle_state: %{locked: true, sentry_mode: true},
           vehicle_config: %{car_type: "models2", trim_badging: "p90d"}
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ ~r/<p class="subtitle is-6">Model S P90D<\/p>/
      assert html =~ table_row("Status", "online")
      assert html =~ table_row("Plugged in", "no")
      assert html =~ table_row("Range \\(typical\\)", "321.9 km")
      assert html =~ table_row("Range \\(est.\\)", "289.7 km")
      assert html =~ table_row("Range \\(rated\\)", "281.6 km")
      assert html =~ table_row("State of Charge", "69%")
      assert html =~ table_row("Locked", "yes")
      assert html =~ table_row("Sentry Mode", "yes")
      assert html =~ table_row("Outside temperature", "24 °C")
      assert html =~ table_row("Inside temperature", "23.2 °C")
    end

    @tag :signed_in
    test "renders current vehicle stats [:charging]", %{conn: conn} do
      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             timestamp: 0,
             charger_power: 50,
             ideal_battery_range: 200,
             est_battery_range: 180,
             battery_range: 175,
             charging_state: "Charging",
             charge_energy_added: "4.32",
             charge_port_latch: "Engaged",
             charge_port_door_open: true,
             scheduled_charging_start_time: 1_565_620_707,
             charge_limit_soc: 85
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "charging")
      assert html =~ table_row("Plugged in", "yes")
      assert html =~ table_row("Range \\(typical\\)", "321.9 km")
      assert html =~ table_row("Range \\(est.\\)", "289.7 km")
      assert html =~ table_row("Range \\(rated\\)", "281.6 km")
      assert html =~ table_row("Charged", "4.32 kWh")
      assert html =~ table_row("Charger Power", "50 kW")

      assert html =~
               table_row(
                 "Scheduled charging",
                 "<span data-date=\"2019-08-12T14:38:27Z\" phx-hook=\"LocalTime\">"
               )

      assert html =~ table_row("Charge limit", "85%")
    end

    @tag :signed_in
    test "renders current vehicle stats [:charging_complete]", %{conn: conn} do
      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             timestamp: 0,
             charger_power: 50,
             ideal_battery_range: 200,
             est_battery_range: 180,
             charging_state: "Charging",
             charge_energy_added: "4.32",
             charge_port_latch: "Engaged",
             charge_port_door_open: true,
             scheduled_charging_start_time: 1_565_620_707,
             charge_limit_soc: 85
           }
         )},
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           charge_state: %{
             timestamp: 0,
             charger_power: 50,
             ideal_battery_range: 200,
             est_battery_range: 180,
             charging_state: "Charging",
             charge_energy_added: "4.32",
             charge_port_latch: "Engaged",
             charge_port_door_open: true,
             scheduled_charging_start_time: 1_565_620_707,
             charge_limit_soc: 85
           }
         )},
        {:ok,
         online_event(
           display_name: "FooCar",
           charge_state: %{
             timestamp: 0,
             charger_power: 50,
             ideal_battery_range: 200,
             est_battery_range: 180,
             charging_state: "Complete",
             charge_energy_added: "4.32",
             charge_port_latch: "Engaged",
             charge_port_door_open: true
           }
         )}
      ]

      :ok = start_vehicles(events)

      :timer.sleep(100)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "charging complete")
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
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "driving")
      assert html =~ table_row("Speed", "48 km/h")
    end

    @tag :signed_in
    test "renders current vehicle stats [:updating]", %{conn: conn} do
      alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           vehicle_state: %{
             car_version: "2019.8.4 530d1d3",
             software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: "installing"}
           }
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "updating")
    end

    @tag :signed_in
    test "renders current vehicle stats [:asleep]", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{display_name: "FooCar", state: "asleep"}}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "asleep")
    end

    @tag :signed_in
    test "renders current vehicle stats [:offline]", %{conn: conn} do
      events = [
        {:ok, %TeslaApi.Vehicle{display_name: "FooCar", state: "offline"}}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "offline")
    end

    @tag :signed_in
    test "renders current vehicle stats [:falling asleep]", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 1})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)

      :timer.sleep(100)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "falling asleep")
    end

    @tag :capture_log
    @tag :signed_in
    test "renders current vehicle stats [:unavailable]", %{conn: conn} do
      events = [
        {:error, :unkown}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6"><\/p>/
      assert html =~ table_row("Status", "unavailable")
    end

    @tag :signed_in
    test "displays imperial units", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{unit_of_length: :mi, unit_of_temperature: :F})

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
           charge_state: %{ideal_battery_range: 200, est_battery_range: 180, battery_range: 175},
           climate_state: %{is_preconditioning: false, outside_temp: 24, inside_temp: 23.2}
         )}
      ]

      :ok = start_vehicles(events)

      conn = get(conn, Routes.car_path(conn, :index))

      assert html = response(conn, 200)
      assert html =~ ~r/<p class="title is-6">FooCar<\/p>/
      assert html =~ table_row("Status", "driving")
      assert html =~ table_row("Range \\(typical\\)", "200.0 mi")
      assert html =~ table_row("Range \\(est.\\)", "180.0 mi")
      assert html =~ table_row("Range \\(rated\\)", "175.0 mi")
      assert html =~ table_row("Speed", "30 mph")
      assert html =~ table_row("Outside temperature", "75.2 °F")
      assert html =~ table_row("Inside temperature", "73.8 °F")
    end
  end

  describe "supsend" do
    setup %{conn: conn} do
      {:ok, conn: put_req_header(conn, "accept", "application/json")}
    end

    test "suspends logging", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 60})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)

      %Car{id: id} = Log.get_car_by_eid(4242)

      conn = put(conn, Routes.car_path(conn, :suspend_logging, id))

      assert "" == response(conn, 204)
    end

    test "returns error if suspending is not possible", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 60})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: true}
         )}
      ]

      :ok = start_vehicles(events)

      %Car{id: id} = Log.get_car_by_eid(4242)

      conn = put(conn, Routes.car_path(conn, :suspend_logging, id))
      assert "preconditioning" == json_response(conn, 412)["error"]
    end
  end

  describe "resume" do
    test "resumes logging", %{conn: conn} do
      alias TeslaMate.Vehicles.Vehicle.Summary

      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 1})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false}
         )}
      ]

      :ok = start_vehicles(events)
      :timer.sleep(100)

      %Car{id: id} = Log.get_car_by_eid(4242)
      %Summary{state: :suspended} = TeslaMate.Vehicles.summary(id)

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
             vehicle_id: 404
           }
         ]}
      )

    :ok
  end
end
