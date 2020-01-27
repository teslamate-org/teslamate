defmodule TeslaMateWeb.CarLive.SummaryTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate
  alias TeslaMate.{Locations, Settings, Log, Repo}

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
      _car = car_fixture(%{suspend_min: 60_000, suspend_after_idle_min: 60_000})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false},
           vehicle_state: %{sentry_mode: false, locked: true, car_version: ""}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, parent_view, _html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      [view] = children(parent_view)
      html = render(view)

      assert table_row(html, "Status", "online")

      assert "try to sleep" ==
               html
               |> Floki.parse_document!()
               |> Floki.find("a[phx-click=suspend_logging]")
               |> Floki.text()

      # Suspend
      render_click(view, :suspend_logging)

      TestHelper.eventually(
        fn ->
          assert view |> render() |> table_row("Status", "falling asleep")
        end,
        delay: 5
      )
    end

    for {msg, id, status, settings, attrs} <- [
          {"Car is unlocked", 0, "online", %{}, vehicle_state: %{locked: false, car_version: ""}},
          {"Sentry mode is enabled", 0, "online", %{req_not_unlocked: true},
           vehicle_state: %{sentry_mode: true, locked: true, car_version: ""}},
          {"Shift state present", 0, "online", %{req_no_shift_state_reading: true},
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0, shift_state: "P"}},
          {"Temperature readings", 0, "online", %{req_no_temp_reading: true},
           climate_state: %{outside_temp: 10.0}},
          {"Temperature readings", 1, "online", %{req_no_temp_reading: true},
           climate_state: %{inside_temp: 10.0}},
          {"Preconditioning", 0, "online", %{}, climate_state: %{is_preconditioning: true}},
          {"Driver present", 0, "online", %{},
           vehicle_state: %{is_user_present: true, car_version: ""}},
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
            %{suspend_min: 60_000, suspend_after_idle_min: 60_000},
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
                 vehicle_state: %{sentry_mode: false, locked: true, car_version: ""}
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
        assert table_row(html, "Status", unquote(Macro.escape(status)))

        assert [{"a", [_, _, {"disabled", "disabled"}], [unquote(msg)]}] =
                 html
                 |> Floki.parse_document!()
                 |> Floki.find(".button.is-danger")
      end
    end

    @tag :signed_in
    test "hides suspend button if sleep mode is disabled", %{conn: conn} do
      _car =
        car_fixture(%{sleep_mode_enabled: false, suspend_min: 60, suspend_after_idle_min: 60})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           vehicle_state: %{sentry_mode: false, locked: true, car_version: ""}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, _view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.find("a[phx-click=suspend_logging]")
    end

    @tag :signed_in
    test "disables suspend button if sleep mode is disabled for locations", %{conn: conn} do
      car = car_fixture(%{sleep_mode_enabled: true, suspend_min: 60, suspend_after_idle_min: 60})

      assert {:ok, _geofence} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: -50.606,
                 longitude: 165.972,
                 radius: 500,
                 sleep_mode_blacklist: [car]
               })

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: -50.606262, longitude: 165.972475},
           vehicle_state: %{sentry_mode: false, locked: true, car_version: ""}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, _view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert ["disabled"] =
               html
               |> Floki.parse_document!()
               |> Floki.find("a[phx-click=suspend_logging]")
               |> Floki.attribute("disabled")
    end
  end

  describe "resume" do
    @tag :signed_in
    test "resumes logging", %{conn: conn} do
      _car = car_fixture(%{suspend_min: 60_000, suspend_after_idle_min: 60_000})

      events = [
        {:ok,
         online_event(
           display_name: "FooCar",
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0},
           climate_state: %{is_preconditioning: false},
           vehicle_state: %{sentry_mode: false, locked: true, car_version: ""}
         )}
      ]

      :ok = start_vehicles(events)

      assert {:ok, parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert table_row(html, "Status", "online")

      assert "try to sleep" ==
               html
               |> Floki.parse_document!()
               |> Floki.find("a[phx-click=suspend_logging]")
               |> Floki.text()

      [view] = children(parent_view)

      # Suspend
      render_click(view, :suspend_logging)

      TestHelper.eventually(
        fn ->
          assert html = render(view)
          assert table_row(html, "Status", "falling asleep")

          assert "cancel sleep attempt" ==
                   html
                   |> Floki.parse_document!()
                   |> Floki.find("a[phx-click=resume_logging]")
                   |> Floki.text()
        end,
        delay: 5
      )

      # Resume
      render_click(view, :resume_logging)
      assert html = render(view)
      assert table_row(html, "Status", "online")
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

      assert {"span", _, [{"span", [{"class", "mdi mdi-alert-box"}], _}]} =
               html
               |> Floki.parse_document!()
               |> Floki.find(".icons .icon")
               |> Enum.find(
                 &match?({"span", [_, {"data-tooltip", "Health check failed"}], _}, &1)
               )
    end
  end

  describe "spinner" do
    @tag :signed_in
    @tag :capture_log
    test "shows spinner if fetching vehicle data on first render", %{conn: conn} do
      events = [
        fn ->
          :timer.sleep(10_0000)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicles(events)

      assert {:ok, _view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert [
               {"span",
                [
                  {"class", "spinner tooltip has-tooltip-top has-tooltip-left-mobile"},
                  {"data-tooltip", "Fetching vehicle data ..."}
                ], _}
             ] =
               html
               |> Floki.parse_document!()
               |> Floki.find(".icons .spinner")
    end

    @tag :signed_in
    @tag :capture_log
    test "shows spinner while fetching vehicle data", %{conn: conn} do
      events = [
        {:ok, online_event()},
        fn ->
          :timer.sleep(50)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicles(events)

      assert {:ok, view, _html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      TestHelper.eventually(
        fn ->
          html = render(view)

          assert [
                   {"span",
                    [
                      {"class", "spinner tooltip has-tooltip-top has-tooltip-left-mobile"},
                      {"data-tooltip", "Fetching vehicle data ..."}
                    ], _}
                 ] =
                   html
                   |> Floki.parse_document!()
                   |> Floki.find(".icons .spinner")
        end,
        delay: 20
      )
    end
  end

  describe "tags" do
    @tag :signed_in
    @tag :capture_log
    test "shows spinner while fetching vehicle data ", %{conn: conn} do
      events = [
        {:ok, online_event()},
        fn ->
          :timer.sleep(50)
          {:ok, online_event()}
        end
      ]

      :ok = start_vehicles(events)

      assert {:ok, view, _html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      TestHelper.eventually(
        fn ->
          html = render(view)

          assert [
                   {"span",
                    [
                      {"class", "spinner tooltip has-tooltip-top has-tooltip-left-mobile"},
                      {"data-tooltip", "Fetching vehicle data ..."}
                    ], _}
                 ] =
                   html
                   |> Floki.parse_document!()
                   |> Floki.find(".icons .spinner")
        end,
        delay: 20
      )
    end

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
               |> Floki.parse_document!()
               |> Floki.find(".icons .icon")
               |> Enum.find(
                 &match?({"span", [_, {"data-tooltip", "Software Update available"}], _}, &1)
               )
    end

    @tag :signed_in
    @tag :capture_log
    test "shows snowflake if usable_battery_level differs from battery_level", %{conn: conn} do
      events = [
        {:ok, online_event()},
        {:ok, online_event(charge_state: %{battery_level: 73, usable_battery_level: 70})},
        {:error, :unknown}
      ]

      :ok = start_vehicles(events)

      Process.sleep(300)

      assert {:ok, _parent_view, html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://localhost"})

      assert {"span", _, [{"span", [{"class", "mdi mdi-snowflake"}], _}]} =
               html
               |> Floki.parse_document!()
               |> Floki.find(".icons .icon")
               |> Enum.find(
                 &match?({"span", [_, {"data-tooltip", "Reduced Battery Range"}], _}, &1)
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
