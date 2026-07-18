defmodule TeslaMateWeb.MaintenanceLiveTest do
  use TeslaMateWeb.ConnCase

  alias Plug.BasicAuth
  alias TeslaMate.{Log, RuntimeHealth}
  alias TeslaMate.Log.{ChargingProcess, Drive, Position}
  alias TeslaMate.Repo
  alias TeslaMate.Vehicles.Vehicle.Summary

  setup do
    keys = [:build_info, :file_logging, :maintenance_actions, :operations_auth]
    previous = Map.new(keys, &{&1, Application.get_env(:teslamate, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:teslamate, key)
        {key, value} -> Application.put_env(:teslamate, key, value)
      end)
    end)

    :ok
  end

  test "shows the scoped read-only empty state", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/maintenance")

    assert has_element?(view, "#maintenance-read-only")
    assert has_element?(view, "#maintenance-summary")
    assert has_element?(view, "#maintenance-empty")
    assert has_element?(view, "#maintenance-refresh[phx-click=refresh]")
    refute has_element?(view, "#maintenance-findings")

    assert html =~ "Read-only. TeslaMate has not changed any data."
    assert html =~ "No long-running open drives or charging sessions found."
    assert html =~ ~s(href="/maintenance")
  end

  test "shows long-running sessions without claiming corruption", %{conn: conn} do
    now = DateTime.utc_now()
    car = car_fixture(%{name: "Atlas"})

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(now, -3 * 24 * 60 * 60, :second)
      )

    long_running_charging_process =
      charging_process_fixture(car,
        start_date: DateTime.add(now, -4 * 24 * 60 * 60, :second)
      )

    recent_drive =
      drive_fixture(car,
        start_date: DateTime.add(now, -60, :second)
      )

    assert {:ok, view, _html} = live(conn, "/maintenance")

    assert has_element?(
             view,
             "#finding-drive-#{long_running_drive.id}[data-finding-code=long_running_open_drive]"
           )

    assert has_element?(
             view,
             "#finding-charging_process-#{long_running_charging_process.id}[data-finding-code=long_running_open_charging_process]"
           )

    refute has_element?(view, "#finding-drive-#{recent_drive.id}")
    refute has_element?(view, "#maintenance-empty")

    html = render(view)
    assert html =~ "Atlas"
    assert html =~ "Drive ##{long_running_drive.id}"
    assert html =~ "Charging session ##{long_running_charging_process.id}"
    assert html =~ "A long-running session is not automatically corrupt."
  end

  test "refreshes the report without exposing maintenance mutations", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, "/maintenance")
    assert has_element?(view, "#maintenance-empty")

    car = car_fixture()

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(DateTime.utc_now(), -3 * 24 * 60 * 60, :second)
      )

    view
    |> element("#maintenance-refresh")
    |> render_click()

    assert has_element?(view, "#finding-drive-#{long_running_drive.id}")
    refute has_element?(view, "#maintenance-empty")

    html = render(view) |> Floki.parse_document!()

    assert ["refresh"] ==
             html
             |> Floki.find("button[phx-click]")
             |> Floki.attribute("phx-click")

    assert [] == Floki.find(html, "form")
    assert [] == Floki.find(html, "[phx-click=close], [phx-click=delete], [phx-click=repair]")
  end

  test "shows build identity and per-car runtime health", %{conn: conn} do
    Application.put_env(:teslamate, :build_info,
      source: "teslamate-org/teslamate",
      ref: "refs/heads/main",
      revision: "abcdef1234567890",
      built_at: "2026-07-18T09:00:00Z"
    )

    start_supervised!({RuntimeHealth, name: RuntimeHealth, mqtt_enabled: true})

    RuntimeHealth.record_summary(42, :online)
    RuntimeHealth.record_api(42, {:ok, %{}})
    RuntimeHealth.record_stream(42, :inactive)
    RuntimeHealth.record_mqtt_connection(:up)
    RuntimeHealth.record_mqtt_publish(42, :ok)
    assert %{vehicles: [%{car_id: 42}]} = RuntimeHealth.report()

    assert {:ok, view, html} = live(conn, "/maintenance")

    assert has_element?(view, "#operations-overview")
    assert has_element?(view, "#operations-build-version")
    assert has_element?(view, "#runtime-health #runtime-car-42")
    assert html =~ "teslamate-org/teslamate"
    assert html =~ "abcdef1234567890"
    assert html =~ "Car 42"
  end

  test "shows only a bounded redacted log tail behind authentication", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "teslamate-maintenance-#{System.unique_integer()}.log")

    File.write!(path, "first line\ntoken=top-secret\nlatest line\n")
    on_exit(fn -> File.rm(path) end)

    Application.put_env(:teslamate, :file_logging, enabled: true, path: path)
    enable_operations_auth()

    assert {:ok, view, html} = live(authenticate(conn), "/maintenance")

    assert has_element?(view, "#maintenance-logs")
    assert has_element?(view, "#maintenance-log-tail")
    assert html =~ "first line"
    assert html =~ "token=[REDACTED]"
    assert html =~ "latest line"
    refute html =~ "top-secret"
    refute html =~ path
  end

  test "confirms and safely closes an eligible session", %{conn: conn} do
    car = car_fixture()
    start_date = DateTime.add(DateTime.utc_now(), -3 * 24 * 60 * 60, :second)
    drive = drive_fixture(car, start_date: start_date)

    vehicles_name = :"maintenance_live_vehicles_#{System.unique_integer([:positive])}"

    start_supervised!(
      {VehiclesMock,
       name: vehicles_name, pid: self(), summary: %Summary{state: :online, car: car}}
    )

    Application.put_env(:teslamate, :maintenance_actions,
      enabled: true,
      vehicles: {VehiclesMock, vehicles_name}
    )

    enable_operations_auth()

    position_fixture(car, drive, DateTime.add(start_date, 60, :second), 100.0)
    position_fixture(car, drive, DateTime.add(start_date, 180, :second), 101.0)

    assert {:ok, view, _html} = live(authenticate(conn), "/maintenance")
    assert has_element?(view, "#maintenance-actions-enabled")
    assert has_element?(view, "#finding-drive-#{drive.id}-close")

    view
    |> element("#finding-drive-#{drive.id}-close")
    |> render_click()

    assert has_element?(view, "#maintenance-close-modal")
    assert has_element?(view, "#maintenance-confirm-close")

    view
    |> element("#maintenance-confirm-close")
    |> render_click()

    refute has_element?(view, "#maintenance-close-modal")
    refute has_element?(view, "#finding-drive-#{drive.id}")
    assert has_element?(view, "#maintenance-flash-info", "Session closed.")
    assert %Drive{end_date: %DateTime{}} = Repo.get!(Drive, drive.id)
  end

  test "explains when current vehicle activity cannot be verified", %{conn: conn} do
    car = car_fixture()
    start_date = DateTime.add(DateTime.utc_now(), -3 * 24 * 60 * 60, :second)
    drive = drive_fixture(car, start_date: start_date)

    vehicles_name = :"maintenance_live_vehicles_#{System.unique_integer([:positive])}"

    start_supervised!(
      {VehiclesMock, name: vehicles_name, pid: self(), summary: %Summary{state: :start, car: car}}
    )

    Application.put_env(:teslamate, :maintenance_actions,
      enabled: true,
      vehicles: {VehiclesMock, vehicles_name}
    )

    enable_operations_auth()

    assert {:ok, view, _html} = live(authenticate(conn), "/maintenance")

    view
    |> element("#finding-drive-#{drive.id}-close")
    |> render_click()

    view
    |> element("#maintenance-confirm-close")
    |> render_click()

    assert has_element?(
             view,
             "#maintenance-flash-error",
             "The session could not be closed. Nothing was changed."
           )

    assert has_element?(view, "#finding-drive-#{drive.id}")
    assert %Drive{end_date: nil} = Repo.get!(Drive, drive.id)

    position_fixture(car, drive, DateTime.add(start_date, 60, :second), 100.0)
    position_fixture(car, drive, DateTime.add(start_date, 180, :second), 101.0)
    :ok = VehiclesMock.set_summary(vehicles_name, %Summary{state: :online, car: car})

    view
    |> element("#finding-drive-#{drive.id}-close")
    |> render_click()

    view
    |> element("#maintenance-confirm-close")
    |> render_click()

    assert has_element?(view, "#maintenance-flash-info", "Session closed.")
    refute has_element?(view, "#maintenance-flash-error")
    refute has_element?(view, "#finding-drive-#{drive.id}")
    assert %Drive{end_date: %DateTime{}} = Repo.get!(Drive, drive.id)
  end

  defp car_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          eid: unique,
          vid: unique,
          vin: "maintenance-#{unique}",
          model: "3"
        },
        attrs
      )

    {:ok, car} = Log.create_car(attrs)
    car
  end

  defp drive_fixture(car, attrs) do
    attrs = Enum.into(attrs, %{car_id: car.id})
    Repo.insert!(struct!(Drive, attrs))
  end

  defp charging_process_fixture(car, attrs) do
    attrs = Enum.into(attrs, %{car_id: car.id})

    position =
      Repo.insert!(%Position{
        car_id: car.id,
        date: Map.fetch!(attrs, :start_date),
        latitude: Decimal.new("0"),
        longitude: Decimal.new("0")
      })

    attrs = Map.put(attrs, :position_id, position.id)
    Repo.insert!(struct!(ChargingProcess, attrs))
  end

  defp position_fixture(car, drive, date, odometer) do
    Repo.insert!(%Position{
      car_id: car.id,
      drive_id: drive.id,
      date: date,
      latitude: Decimal.new("0"),
      longitude: Decimal.new("0"),
      odometer: odometer,
      ideal_battery_range_km: Decimal.new("300"),
      rated_battery_range_km: Decimal.new("250")
    })
  end

  defp enable_operations_auth do
    Application.put_env(:teslamate, :operations_auth,
      required: true,
      username: "operator",
      password: "secret"
    )
  end

  defp authenticate(conn) do
    put_req_header(conn, "authorization", BasicAuth.encode_basic_auth("operator", "secret"))
  end
end
