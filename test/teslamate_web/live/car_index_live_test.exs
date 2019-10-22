defmodule TeslaMateWeb.CarLive.Indextest do
  use TeslaMateWeb.ConnCase
  use TeslaMate.VehicleCase

  alias TeslaApi.Vehicle.State.VehicleState.SoftwareUpdate
  alias TeslaMate.Settings

  describe "base URL" do
    @tag :signed_in
    test "initiall sets the base URL", %{conn: conn} do
      :ok = start_vehicles([{:ok, online_event()}])

      assert %Settings.Settings{base_url: nil} = Settings.get_settings!()

      assert {:ok, _parent_view, _html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://example.com "})

      assert %Settings.Settings{base_url: "http://example.com"} = Settings.get_settings!()
    end

    @tag :signed_in
    test "does not update the base URL if exists already", %{conn: conn} do
      :ok = start_vehicles([{:ok, online_event()}])

      assert {:ok, _settings} =
               Settings.get_settings!()
               |> Settings.update_settings(%{base_url: "https://example.com"})

      assert {:ok, _parent_view, _html} =
               live(conn, "/", connect_params: %{"baseUrl" => "http://foo.bar/ "})

      assert %Settings.Settings{base_url: "https://example.com"} = Settings.get_settings!()
    end

    @tag :signed_in
    @tag :capture_log
    test "handles invalid base URLs", %{conn: conn} do
      :ok = start_vehicles([{:ok, online_event()}])

      for base_url <- [nil, "udp://10.0.0.1", "", "example.com"] do
        assert {:ok, _parent_view, _html} =
                 live(conn, "/", connect_params: %{"baseUrl" => base_url})
      end

      assert %Settings.Settings{base_url: nil} = Settings.get_settings!()
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
