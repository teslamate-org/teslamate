defmodule TeslaMateWeb.CarLive.Indextest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaMate.Settings.{GlobalSettings, CarSettings}
  alias TeslaMate.{Settings, Log, Api, Vehicles}
  alias TeslaMate.Log.Car

  import Mock

  describe "base URL" do
    @tag :signed_in
    test "sets the base URL", %{conn: conn} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      :ok = start_vehicles([{:ok, online_event(now_ts)}])

      assert %GlobalSettings{base_url: nil} = Settings.get_global_settings!()

      assert {:ok, _parent_view, _html} =
               conn
               |> put_connect_params(%{"baseUrl" => "http://example.com "})
               |> live("/")

      assert %GlobalSettings{base_url: "http://example.com"} = Settings.get_global_settings!()
    end

    @tag :signed_in
    test "does not update the base URL if exists already", %{conn: conn} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      :ok = start_vehicles([{:ok, online_event(now_ts)}])

      assert {:ok, _settings} =
               Settings.get_global_settings!()
               |> Settings.update_global_settings(%{base_url: "https://example.com"})

      assert {:ok, _parent_view, _html} =
               conn
               |> put_connect_params(%{"baseUrl" => "http://foo.bar/ "})
               |> live("/")

      assert %GlobalSettings{base_url: "https://example.com"} = Settings.get_global_settings!()
    end

    @tag :signed_in
    @tag :capture_log
    test "handles invalid base URLs", %{conn: conn} do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      :ok = start_vehicles([{:ok, online_event(now_ts)}])

      for base_url <- [nil, "udp://10.0.0.1", "", "example.com"] do
        assert {:ok, _parent_view, _html} =
                 conn
                 |> put_connect_params(%{"baseUrl" => base_url})
                 |> live("/")
      end

      assert %GlobalSettings{base_url: nil} = Settings.get_global_settings!()
    end
  end

  describe "without a logged vehicle" do
    @vehicle %TeslaApi.Vehicle{
      display_name: "Foo",
      id: 11243,
      vehicle_id: 90211,
      vin: "absadkalfs"
    }

    setup do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
        )

      {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: []})
      {:ok, answer} = Agent.start_link(fn -> {:ok, []} end)

      [answer: answer, list_vehicles: fn -> Agent.get(answer, & &1) end]
    end

    defp answer(agent, value), do: Agent.update(agent, fn _ -> value end)

    defp api_calls, do: length(call_history(Api))

    defp reload(view) do
      render_click(view, "reload_vehicles")
      render_async(view)
    end

    defp button_enabled?(view) do
      has_element?(view, "button[phx-click=reload_vehicles]:not([disabled])")
    end

    @tag :signed_in
    test "explains that nothing was found at start-up", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/")
      assert html =~ "No vehicle is logged"
      assert html =~ "No vehicle was found when TeslaMate started"
      assert button_enabled?(view)
    end

    @tag :signed_in
    test "explains known vehicles without a logger", %{conn: conn} do
      {:ok, %Car{}} =
        %Car{settings: %CarSettings{enabled: false}}
        |> Car.changeset(%{vid: 90211, eid: 11243, vin: "absadkalfs"})
        |> Log.create_or_update_car()

      assert {:ok, view, html} = live(conn, "/")
      assert html =~ "Data collection is disabled for the known vehicles"
      assert html =~ ~s(href="/settings")
      refute html =~ "when TeslaMate started"
      assert button_enabled?(view)
    end

    @tag :signed_in
    test "starts the logger for a vehicle that showed up", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        :ok = answer(answer, {:ok, [@vehicle]})
        calls = api_calls()

        assert render_click(view, "reload_vehicles") =~ "is-loading"
        html = render_async(view)

        assert html =~ ~s(id="car_)
        refute html =~ "No vehicle is logged"
        assert api_calls() == calls + 1
        assert [%Car{vin: "absadkalfs"}] = Log.list_cars()
      end
    end

    @tag :signed_in
    test "explains an account without vehicles", ctx do
      %{conn: conn, list_vehicles: list_vehicles} = ctx

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        html = reload(view)

        assert html =~ "does not contain a vehicle yet"
        assert button_enabled?(view)
      end
    end

    @tag :signed_in
    test "explains a rate limited API", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx
      :ok = answer(answer, {:error, :too_many_request, 30})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        assert reload(view) =~ "rate limit was exceeded"
        assert button_enabled?(view)
      end
    end

    @tag :signed_in
    test "explains a failed API call", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx
      :ok = answer(answer, {:error, :timeout})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        assert reload(view) =~ "Fetching the vehicles from the Tesla API failed: :timeout"
        assert button_enabled?(view)
      end
    end

    @tag :signed_in
    test "redirects to the sign in page when the session is gone", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx
      :ok = answer(answer, {:error, :not_signed_in})

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        render_click(view, "reload_vehicles")
        assert_redirect(view, "/sign_in", 1000)
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "reports a crashed reload and re-enables the button", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/")

      with_mock Vehicles, [:passthrough], discover: fn -> exit(:boom) end do
        assert reload(view) =~ "Reloading the vehicles failed"
        assert button_enabled?(view)
      end
    end

    @tag :signed_in
    test "runs one reload per tab at a time", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, "/")
      test_pid = self()

      discover = fn ->
        send(test_pid, :discovering)
        Process.sleep(100)
        {:error, :no_vehicles}
      end

      with_mock Vehicles, [:passthrough], discover: discover do
        render_click(view, "reload_vehicles")
        render_click(view, "reload_vehicles")
        render_async(view)

        assert_receive :discovering
        refute_receive :discovering
      end
    end

    @tag :signed_in
    test "shows the card when the vehicle was reloaded elsewhere", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view, _html} = live(conn, "/")
        :ok = answer(answer, {:ok, [@vehicle]})

        # e.g. the settings page of another tab
        assert {:ok, [_car]} = Vehicles.discover()

        assert render(view) =~ ~s(id="car_)
        refute render(view) =~ "No vehicle is logged"
      end
    end

    @tag :signed_in
    test "concurrent reloads from two tabs start the logger once", ctx do
      %{conn: conn, answer: answer, list_vehicles: list_vehicles} = ctx

      with_mock Api, [:passthrough], list_vehicles: list_vehicles do
        assert {:ok, view_a, _html} = live(conn, "/")
        assert {:ok, view_b, _html} = live(conn, "/")
        :ok = answer(answer, {:ok, [@vehicle]})
        calls = api_calls()

        render_click(view_a, "reload_vehicles")
        render_click(view_b, "reload_vehicles")

        assert render_async(view_a) =~ ~s(id="car_)
        assert render_async(view_b) =~ ~s(id="car_)
        assert api_calls() == calls + 2
        assert [%Car{vin: "absadkalfs"}] = Log.list_cars()
        assert length(Vehicles.list()) == 1
      end
    end
  end

  defp start_vehicles(events) do
    {:ok, _pid} = start_supervised({ApiMock, name: :api_vehicle, events: events, pid: self()})

    {:ok, _pid} =
      start_supervised(
        {TeslaMate.Vehicles,
         vehicle: VehicleMock,
         vehicles: [
           %TeslaApi.Vehicle{
             display_name: "Foo",
             id: 11243,
             vehicle_id: 90211,
             vin: "absadkalfs"
           }
         ]}
      )

    :ok
  end
end
