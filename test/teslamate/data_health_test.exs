defmodule TeslaMate.DataHealthTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.DataHealth
  alias TeslaMate.Log
  alias TeslaMate.Log.{ChargingProcess, Drive, Position}

  @now ~U[2026-07-16 12:00:00.000000Z]
  @open_after_seconds 2 * 24 * 60 * 60

  test "reports old open sessions without claiming that they are corrupt" do
    car = car_fixture(%{name: "Roadrunner"})

    long_running_drive =
      drive_fixture(car,
        start_date: DateTime.add(@now, -3 * 24 * 60 * 60, :second)
      )

    long_running_charging_process =
      charging_process_fixture(car,
        start_date: DateTime.add(@now, -@open_after_seconds - 1, :second)
      )

    boundary_drive =
      drive_fixture(car,
        start_date: DateTime.add(@now, -@open_after_seconds, :second)
      )

    recent_charging_process =
      charging_process_fixture(car,
        start_date: DateTime.add(@now, -60, :second)
      )

    closed_drive =
      drive_fixture(car,
        start_date: DateTime.add(@now, -4 * 24 * 60 * 60, :second),
        end_date: DateTime.add(@now, -4 * 24 * 60 * 60 + 300, :second)
      )

    closed_charging_process =
      charging_process_fixture(car,
        start_date: DateTime.add(@now, -5 * 24 * 60 * 60, :second),
        end_date: DateTime.add(@now, -5 * 24 * 60 * 60 + 300, :second)
      )

    report = DataHealth.report(now: @now, open_after_seconds: @open_after_seconds)

    assert report.read_only?
    refute report.truncated?
    assert report.checked_at == @now
    assert report.open_after_seconds == @open_after_seconds

    assert [drive_finding, charging_finding] = report.findings

    assert drive_finding.id == "drive:#{long_running_drive.id}"
    assert drive_finding.code == :long_running_open_drive
    assert drive_finding.entity_type == :drive
    assert drive_finding.entity_id == long_running_drive.id
    assert drive_finding.car_id == car.id
    assert drive_finding.car_name == "Roadrunner"
    assert drive_finding.started_at == long_running_drive.start_date

    assert charging_finding.id == "charging_process:#{long_running_charging_process.id}"
    assert charging_finding.code == :long_running_open_charging_process
    assert charging_finding.entity_type == :charging_process
    assert charging_finding.entity_id == long_running_charging_process.id

    assert Repo.get!(Drive, long_running_drive.id).end_date == nil
    assert Repo.get!(ChargingProcess, long_running_charging_process.id).end_date == nil
    assert Repo.get!(Drive, boundary_drive.id).end_date == nil
    assert Repo.get!(ChargingProcess, recent_charging_process.id).end_date == nil
    assert Repo.get!(Drive, closed_drive.id).end_date == closed_drive.end_date

    assert Repo.get!(ChargingProcess, closed_charging_process.id).end_date ==
             closed_charging_process.end_date
  end

  test "keeps cars separate" do
    first_car = car_fixture(%{name: nil})
    second_car = car_fixture(%{name: "Second"})

    first_drive =
      drive_fixture(first_car,
        start_date: DateTime.add(@now, -4 * 24 * 60 * 60, :second)
      )

    second_drive =
      drive_fixture(second_car,
        start_date: DateTime.add(@now, -3 * 24 * 60 * 60, :second)
      )

    assert [first, second] = DataHealth.report(now: @now).findings

    assert first.entity_id == first_drive.id
    assert first.car_id == first_car.id
    assert first.car_name == nil

    assert second.entity_id == second_drive.id
    assert second.car_id == second_car.id
    assert second.car_name == "Second"
  end

  test "caps the inbox and marks a truncated report" do
    car = car_fixture()

    oldest =
      drive_fixture(car,
        start_date: DateTime.add(@now, -5 * 24 * 60 * 60, :second)
      )

    second =
      charging_process_fixture(car,
        start_date: DateTime.add(@now, -4 * 24 * 60 * 60, :second)
      )

    _newest =
      drive_fixture(car,
        start_date: DateTime.add(@now, -3 * 24 * 60 * 60, :second)
      )

    report = DataHealth.report(now: @now, limit: 2)

    assert report.truncated?

    assert Enum.map(report.findings, &{&1.entity_type, &1.entity_id}) == [
             {:drive, oldest.id},
             {:charging_process, second.id}
           ]
  end

  test "rejects invalid report options" do
    assert_raise ArgumentError, ~r/open_after_seconds must be a positive integer/, fn ->
      DataHealth.report(open_after_seconds: 0)
    end

    assert_raise ArgumentError, ~r/limit must be a positive integer/, fn ->
      DataHealth.report(limit: -1)
    end
  end

  defp car_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          eid: unique,
          vid: unique,
          vin: "health-#{unique}",
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
end
