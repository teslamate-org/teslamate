defmodule TeslaMate.MaintenanceTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log
  alias TeslaMate.Log.{ChargingProcess, Drive, Position}
  alias TeslaMate.Maintenance
  alias TeslaMate.Vehicles.Vehicle.Summary

  @now ~U[2026-07-18 10:00:00.000000Z]
  @old DateTime.add(@now, -3 * 24 * 60 * 60, :second)

  test "lists only old open sessions as close candidates" do
    car = car_fixture()
    old_drive = drive_fixture(car, @old)
    old_charge = charging_process_fixture(car, DateTime.add(@old, -60, :second))
    recent_drive = drive_fixture(car, DateTime.add(@now, -60, :second))
    closed_drive = drive_fixture(car, @old, end_date: DateTime.add(@old, 300, :second))

    report = Maintenance.candidates(now: @now)

    assert Enum.map(report.candidates, &{&1.entity_type, &1.entity_id}) == [
             {:charging_process, old_charge.id},
             {:drive, old_drive.id}
           ]

    refute Enum.any?(report.candidates, &(&1.entity_id in [recent_drive.id, closed_drive.id]))
    refute report.truncated?
  end

  test "bounds the close candidate list" do
    car = car_fixture()
    drive_fixture(car, DateTime.add(@old, -60, :second))
    drive_fixture(car, @old)

    report = Maintenance.candidates(now: @now, limit: 1)

    assert length(report.candidates) == 1
    assert report.truncated?
  end

  test "closes an eligible drive without allowing the logger to delete it" do
    car = car_fixture()
    drive = drive_fixture(car, @old)

    position_fixture(car, drive, DateTime.add(@old, 60, :second), 100.0)
    position_fixture(car, drive, DateTime.add(@old, 180, :second), 101.0)

    assert {:ok, %{entity_type: :drive, entity_id: id, outcome: :closed}} =
             Maintenance.close(:drive, drive.id, enabled_opts())

    assert id == drive.id
    assert %Drive{end_date: %DateTime{}, distance: distance} = Repo.get!(Drive, drive.id)
    assert distance == 1.0
  end

  test "refuses to delete a drive with insufficient position data" do
    car = car_fixture()
    drive = drive_fixture(car, @old)

    assert {:error, :insufficient_data} =
             Maintenance.close(:drive, drive.id, enabled_opts())

    assert %Drive{end_date: nil} = Repo.get!(Drive, drive.id)
  end

  test "closes an eligible charging process" do
    car = car_fixture()
    charging_process = charging_process_fixture(car, @old)

    assert {:ok, %{entity_type: :charging_process, entity_id: id, outcome: :closed}} =
             Maintenance.close(:charging_process, charging_process.id, enabled_opts())

    assert id == charging_process.id

    assert %ChargingProcess{end_date: %DateTime{}} =
             Repo.get!(ChargingProcess, charging_process.id)
  end

  test "revalidates age and open state at confirmation time" do
    car = car_fixture()
    recent_drive = drive_fixture(car, DateTime.add(@now, -60, :second))
    closed_drive = drive_fixture(car, @old, end_date: DateTime.add(@old, 300, :second))

    assert {:error, :not_eligible} =
             Maintenance.close(:drive, recent_drive.id, enabled_opts())

    assert {:error, :not_eligible} =
             Maintenance.close(:drive, closed_drive.id, enabled_opts())
  end

  test "blocks the matching active logger state" do
    car = car_fixture()
    drive = drive_fixture(car, @old)
    charging_process = charging_process_fixture(car, @old)

    drive_opts = [
      config: [enabled: true],
      now: @now,
      vehicles: start_vehicles_mock(%Summary{state: :driving})
    ]

    charging_opts = [
      config: [enabled: true],
      now: @now,
      vehicles: start_vehicles_mock(%Summary{state: :charging})
    ]

    assert {:error, :vehicle_active} = Maintenance.close(:drive, drive.id, drive_opts)

    assert {:error, :vehicle_active} =
             Maintenance.close(:charging_process, charging_process.id, charging_opts)

    assert Repo.get!(Drive, drive.id).end_date == nil
    assert Repo.get!(ChargingProcess, charging_process.id).end_date == nil
  end

  test "fails closed when vehicle activity cannot be confirmed" do
    car = car_fixture()
    drive = drive_fixture(car, @old)
    activity = fn _car_id, _entity_type -> :unavailable end
    opts = Keyword.put(enabled_opts(), :vehicle_activity, activity)

    assert {:error, :runtime_unavailable} = Maintenance.close(:drive, drive.id, opts)
    assert Repo.get!(Drive, drive.id).end_date == nil
  end

  test "fails closed for an uncertain logger state" do
    car = car_fixture()
    drive = drive_fixture(car, @old)
    vehicles = start_vehicles_mock(%Summary{state: :unavailable})

    assert {:error, :runtime_unavailable} =
             Maintenance.close(:drive, drive.id,
               config: [enabled: true],
               now: @now,
               vehicles: vehicles
             )

    assert Repo.get!(Drive, drive.id).end_date == nil
  end

  test "is disabled by default and rejects unallowlisted requests" do
    car = car_fixture()
    drive = drive_fixture(car, @old)

    assert {:error, :disabled} = Maintenance.close(:drive, drive.id, now: @now)
    assert {:error, :invalid_request} = Maintenance.close(:state, drive.id, enabled_opts())
    assert {:error, :invalid_request} = Maintenance.close(:drive, "#{drive.id}", enabled_opts())
    assert Repo.get!(Drive, drive.id).end_date == nil
  end

  defp enabled_opts do
    [config: [enabled: true], now: @now, vehicle_activity: fn _car_id, _type -> :inactive end]
  end

  defp start_vehicles_mock(summary) do
    name = :"maintenance_vehicles_#{System.unique_integer([:positive])}"

    {VehiclesMock, name: name, pid: self(), summary: summary}
    |> Supervisor.child_spec(id: name)
    |> start_supervised!()

    {VehiclesMock, name}
  end

  defp car_fixture do
    unique = System.unique_integer([:positive])

    {:ok, car} =
      Log.create_car(%{
        eid: unique,
        vid: unique,
        vin: "maintenance-action-#{unique}",
        model: "3"
      })

    car
  end

  defp drive_fixture(car, start_date, attrs \\ []) do
    attrs = attrs |> Enum.into(%{car_id: car.id, start_date: start_date})
    Repo.insert!(struct!(Drive, attrs))
  end

  defp charging_process_fixture(car, start_date) do
    position =
      Repo.insert!(%Position{
        car_id: car.id,
        date: start_date,
        latitude: Decimal.new("0"),
        longitude: Decimal.new("0")
      })

    Repo.insert!(%ChargingProcess{
      car_id: car.id,
      position_id: position.id,
      start_date: start_date
    })
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
end
