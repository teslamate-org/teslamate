defmodule TeslaMateWeb.MaintenanceLiveTest do
  use TeslaMateWeb.ConnCase

  alias Plug.BasicAuth
  alias TeslaMate.Log
  alias TeslaMate.Log.{Drive, Position}
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

  test "keeps maintenance queries and actions disabled by default", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/maintenance")

    assert has_element?(view, "#maintenance-actions-disabled")
    refute has_element?(view, "#maintenance-summary")
    refute has_element?(view, "#maintenance-empty")
    assert has_element?(view, "#maintenance-refresh[phx-click=refresh]")
    refute has_element?(view, "#maintenance-findings")

    assert html =~ "Maintenance actions are disabled."
    assert html =~ ~s(href="/maintenance")
  end

  test "does not expose open sessions while actions are disabled", %{conn: conn} do
    now = DateTime.utc_now()
    car = car_fixture(%{name: "Atlas"})

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(now, -3 * 24 * 60 * 60, :second)
      )

    assert {:ok, view, _html} = live(conn, "/maintenance")
    refute has_element?(view, "#finding-drive-#{long_running_drive.id}")
    refute render(view) =~ "Atlas"
  end

  test "lists eligible sessions only when authenticated actions are enabled", %{conn: conn} do
    Application.put_env(:teslamate, :maintenance_actions, enabled: true)
    enable_operations_auth()

    assert {:ok, view, _html} = live(authenticate(conn), "/maintenance")
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
    assert has_element?(view, "#finding-drive-#{long_running_drive.id}-close")
  end

  test "shows build identity without runtime instrumentation", %{conn: conn} do
    Application.put_env(:teslamate, :build_info,
      source: "teslamate-org/teslamate",
      ref: "refs/heads/main",
      revision: "abcdef1234567890",
      built_at: "2026-07-18T09:00:00Z"
    )

    assert {:ok, view, html} = live(conn, "/maintenance")

    assert has_element?(view, "#operations-overview")
    assert has_element?(view, "#operations-build-version")
    refute has_element?(view, "#runtime-health")
    assert html =~ "teslamate-org/teslamate"
    assert html =~ "abcdef1234567890"
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
