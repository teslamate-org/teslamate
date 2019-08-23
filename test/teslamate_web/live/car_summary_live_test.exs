defmodule TeslaMateWeb.CarLive.SummaryTest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.Settings

  defp table_row(key, value) do
    ~r/<tr>\n?\s*<td>#{key}<\/td>\n?\s*<td.*?>\n?\s*#{value}\n?\s*<\/td>\n?\s*<\/tr>/
  end

  describe "suspend" do
    @tag :signed_in
    test "suspends logging", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 60})

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

      assert {:ok, parent_view, html} = live(conn, "/")
      [view] = children(parent_view)

      assert html = render(view)
      assert html =~ table_row("Status", "online")

      assert html =~
               ~r/a class="button is-info .*?" .*? phx-click="suspend_logging">try to sleep<\/a>/

      render_click(view, :suspend_logging)

      assert html = render(view)
      assert html =~ table_row("Status", "falling asleep")
    end

    for {msg, id, settings, attrs} <- [
          {"Car is unlocked", 0, %{}, vehicle_state: %{locked: false}},
          {"Sentry mode is enabled", 0, %{req_not_unlocked: true},
           vehicle_state: %{sentry_mode: true, locked: true}},
          {"Shift state present", 0, %{req_no_shift_state_reading: true},
           drive_state: %{timestamp: 0, latitude: 0.0, longitude: 0.0, shift_state: "P"}},
          {"Temperature readings", 0, %{req_no_temp_reading: true},
           climate_state: %{outside_temp: 10.0}},
          {"Temperature readings", 1, %{req_no_temp_reading: true},
           climate_state: %{inside_temp: 10.0}},
          {"Preconditioning", 0, %{}, climate_state: %{is_preconditioning: true}},
          {"User present", 0, %{}, vehicle_state: %{is_user_present: true}}
        ] do
      @tag :signed_in
      test "shows warning if suspending is not possible [#{msg}#{id}]", %{conn: conn} do
        settings =
          Map.merge(
            %{suspend_min: 60, suspend_after_idle_min: 60},
            unquote(Macro.escape(settings))
          )

        {:ok, _} =
          Settings.get_settings!()
          |> Settings.update_settings(settings)

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

        assert {:ok, parent_view, html} = live(conn, "/")
        [view] = children(parent_view)
        render_click(view, :suspend_logging)

        assert html = render(view)
        assert html =~ table_row("Status", "online")

        assert html =~
                 ~r/a class="button is-danger .*? disabled>#{unquote(msg)}<\/a>/
      end
    end
  end

  describe "resume" do
    @tag :signed_in
    test "resumes logging", %{conn: conn} do
      {:ok, _} =
        Settings.get_settings!()
        |> Settings.update_settings(%{suspend_min: 60, suspend_after_idle_min: 60})

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

      assert {:ok, parent_view, html} = live(conn, "/")
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
             option_codes: ["MDL3", "BT37"]
           }
         ]}
      )

    :ok
  end
end
