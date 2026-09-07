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

  describe "without vehicles" do
    @vehicle %TeslaApi.Vehicle{
      display_name: "Foo",
      id: 11243,
      vehicle_id: 90211,
      vin: "absadkalfs"
    }

    setup do
      {:ok, api} = Agent.start_link(fn -> {:ok, []} end)
      [api: api]
    end

    defp list_vehicles(api), do: fn -> Agent.get(api, & &1) end

    defp start_empty_vehicles do
      now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      {:ok, _pid} =
        start_supervised(
          {ApiMock, name: :api_vehicle, events: [{:ok, online_event(now_ts)}], pid: self()}
        )

      {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock})
      :ok
    end

    @tag :signed_in
    @tag :capture_log
    test "explains an account without vehicles and reloads on demand", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, view, html} = live(conn, "/")
        assert html =~ "No vehicles found"
        assert html =~ "does not contain a vehicle yet"
        assert html =~ "Reload vehicles"

        # The vehicle shows up in the account only now
        :ok = Agent.update(api, fn _ -> {:ok, [@vehicle]} end)

        assert render_click(view, "reload_vehicles") =~ "is-loading"
        html = render_async(view)

        refute html =~ "No vehicles found"
        assert html =~ ~s(id="car_)
        assert [%Car{vin: "absadkalfs"}] = Log.list_cars()
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "keeps explaining when reloading finds nothing", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, view, _html} = live(conn, "/")
        render_click(view, "reload_vehicles")
        html = render_async(view)

        assert html =~ "does not contain a vehicle yet"
        refute html =~ "is-loading"
        assert html =~ "Reload vehicles"
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "explains a rate limited API", %{conn: conn, api: api} do
      :ok = Agent.update(api, fn _ -> {:error, :too_many_request, 30} end)

      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, _view, html} = live(conn, "/")
        assert html =~ "rate limit was exceeded"
        assert html =~ "Reload vehicles"
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "explains a failed API call", %{conn: conn, api: api} do
      :ok = Agent.update(api, fn _ -> {:error, :timeout} end)

      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, _view, html} = live(conn, "/")
        assert html =~ "Fetching the vehicles from the Tesla API failed: :timeout"
        assert html =~ "Reload vehicles"
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "redirects to the sign in page when reloading finds no session", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, view, _html} = live(conn, "/")

        :ok = Agent.update(api, fn _ -> {:error, :not_signed_in} end)
        render_click(view, "reload_vehicles")

        assert_redirect(view, "/sign_in", 1000)
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "reports a failed reload and re-enables the button", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()
        assert {:ok, view, _html} = live(conn, "/")

        # e.g. a supervisor that is currently down
        :ok = stop_supervised(Vehicles)
        render_click(view, "reload_vehicles")
        html = render_async(view)

        assert html =~ "Reloading the vehicles failed"
        refute html =~ "is-loading"
        refute html =~ ~s(disabled)
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "reports a crashed reload and re-enables the button", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()
        assert {:ok, view, _html} = live(conn, "/")

        with_mock Vehicles, [:passthrough], restart: fn -> exit(:boom) end do
          render_click(view, "reload_vehicles")
          html = render_async(view)

          assert html =~ "Reloading the vehicles failed"
          refute html =~ "is-loading"
        end
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "runs one reload at a time", %{conn: conn, api: api} do
      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()
        assert {:ok, view, _html} = live(conn, "/")

        test_pid = self()

        restart = fn ->
          send(test_pid, :restarting)
          Process.sleep(100)
          :ok
        end

        with_mock Vehicles, [:passthrough], restart: restart do
          render_click(view, "reload_vehicles")
          render_click(view, "reload_vehicles")
          render_async(view)

          assert_receive :restarting
          refute_receive :restarting
        end
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "catches up instead of restarting when a vehicle is logged meanwhile", ctx do
      %{conn: conn, api: api} = ctx

      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()
        assert {:ok, view, _html} = live(conn, "/")

        # Another tab reloads after the vehicle showed up
        :ok = Agent.update(api, fn _ -> {:ok, [@vehicle]} end)
        :ok = Vehicles.restart()
        calls_before = length(call_history(Api))

        html = render_click(view, "reload_vehicles")

        assert html =~ ~s(id="car_)
        refute html =~ "Reload vehicles"
        assert length(call_history(Api)) == calls_before
      end
    end

    @tag :signed_in
    @tag :capture_log
    test "explains disabled data collection alongside an API error", %{conn: conn, api: api} do
      {:ok, %Car{}} =
        %Car{settings: %CarSettings{enabled: false}}
        |> Car.changeset(%{vid: 90211, eid: 11243, vin: "absadkalfs"})
        |> Log.create_or_update_car()

      :ok = Agent.update(api, fn _ -> {:error, :timeout} end)

      with_mock Api, [:passthrough], list_vehicles: list_vehicles(api) do
        :ok = start_empty_vehicles()

        assert {:ok, _view, html} = live(conn, "/")
        assert html =~ "Data collection is disabled for all vehicles"
        assert html =~ "Fetching the vehicles from the Tesla API failed: :timeout"
        assert html =~ "Reload vehicles"
      end
    end

    @tag :signed_in
    test "explains when data collection is disabled for every vehicle", %{conn: conn} do
      {:ok, %Car{}} =
        %Car{settings: %CarSettings{enabled: false}}
        |> Car.changeset(%{vid: 90211, eid: 11243, vin: "absadkalfs"})
        |> Log.create_or_update_car()

      {:ok, _pid} = start_supervised({Vehicles, vehicle: VehicleMock, vehicles: [@vehicle]})

      assert {:ok, _view, html} = live(conn, "/")
      assert html =~ "Data collection is disabled for all vehicles"
      refute html =~ "Reload vehicles"
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
