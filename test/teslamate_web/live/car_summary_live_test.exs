defmodule TeslaMateWeb.CarLive.SummaryTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate
  alias TeslaMate.{Settings, Log, Repo}

  defp table_row(key, value) do
    ~r/<tr>\n?\s*<td class=\"has-text-weight-medium\">#{key}<\/td>\n?\s*<td.*?>\n?\s*#{value}\n?\s*<\/td>\n?\s*<\/tr>/
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

  describe "suspend" do
    @tag :signed_in
    test "suspends logging", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 60})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false},
           vehicle_state: %{sentry_mode: false, locked: true}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      [view] = children(parent_view)

      assert html = render(view)
      assert html =~ table_row("Status", "online")

      assert html =~
               ~r/a class="button is-info .*?" .*? phx-click="suspend_logging">try to sleep<\/a>/

      render_click(view, :suspend_logging)

      assert html = render(view)
      assert html =~ table_row("Status", "falling asleep")
    end

    for {msg, id, status, settings, attrs} <- [
          {"Car is unlocked", 0, "online", %{}, vehicle_state: %{locked: false}},
          {"Sentry mode is enabled", 0, "online", %{req_not_unlocked: true},
           vehicle_state: %{sentry_mode: true, locked: true}},
          {"Shift state present", 0, "online", %{req_no_shift_state_reading: true},
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0, shift_state: "P"}},
          {"Temperature readings", 0, "online", %{req_no_temp_reading: true},
           climate_state: %{outside_temp: 10.0}},
          {"Temperature readings", 1, "online", %{req_no_temp_reading: true},
           climate_state: %{inside_temp: 10.0}},
          {"Preconditioning", 0, "online", %{}, climate_state: %{is_preconditioning: true}},
          {"User present", 0, "online", %{}, vehicle_state: %{is_user_present: true}},
          {"Update in progress", 0, "updating", %{},
           vehicle_state: %{
             car_version: "v9",
             software_update: %SoftwareUpdate{expected_duration_sec: 2700, status: "installing"}
           }}
        ] do
      @tag :signed_in
      test "shows warning if suspending is not possible [#{msg}#{id}]", %{conn: conn} do
        settings =
          Map.merge(
            %{suspend_min: 60, suspend_after_idle_min: 60},
            unquote(Macro.escape(settings))
          )

        _car = car_fixture(settings)

        events = [
          {:ok,
           online_event(
             Keyword.merge(
               [
                 display_name: "FooCar",
                 drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
                 vehicle_state: %{sentry_mode: false, locked: true}
               ],
               unquote(Macro.escape(attrs))
             )
           )}
        ]

        :ok = start_vehicles(events)

        assert {:ok, parent_view, html} =
                 live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

        [view] = children(parent_view)
        render_click(view, :suspend_logging)

        assert html = render(view)
        assert html =~ table_row("Status", unquote(Macro.escape(status)))

        assert [{"a", [_, _, {"disabled", "disabled"}], [unquote(msg)]}] =
                 Floki.find(html, ".button.is-danger")
      end
    end
  end

  describe "resume" do
    @tag :signed_in
    test "resumes logging", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60, suspend_after_idle_min: 60})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false},
           vehicle_state: %{sentry_mode: false, locked: true}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      [view] = children(parent_view)
      render_click(view, :suspend_logging)

      assert html = render(view)
      assert html =~ table_row("Status", "falling asleep")

      assert html =~
               ~r/a class="button is-info .*?" .*? phx-click="resume_logging">cancel sleep attempt<\/a>/

      render_click(view, :resume_logging)

      assert html = render(view)
      assert html =~ table_row("Status", "online")
    end
  end

  describe "health status" do
    @tag :signed_in
    @tag :capture_log
    test "reports health status", %{conn: conn} do
      events = [
        {:ok, online_event(display_name: "FooCar")},
        {:ok, online_event(display_name: "FooCar")},
        {:error, :unknown}
      ]

      :ok = start_vehicles(events)

      Process.sleep(300)

      assert {:ok, _parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert [{"span", _, _}] = html |> Floki.find(".health")
    end
  end

  describe "tags" do
    @tag :signed_in
    @tag :capture_log
    test "shows tag if update is available ", %{conn: conn} do
      events = [
        {:ok, online_event()},
        {:ok, update_event("available", nil)},
        {:error, :unknown}
      ]

      :ok = start_vehicles(events)

      Process.sleep(300)

      assert {:ok, _parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert {"span", _, [{"span", [{"class", "mdi mdi-gift-outline"}], _}]} =
               html
               |> Floki.find(".icons .icon")
               |> Enum.find(
                 &match?({"span", [_, {"data-tooltip", "Software Update available"}], _}, &1)
               )
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
