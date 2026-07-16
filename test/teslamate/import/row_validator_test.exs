defmodule TeslaMate.Import.RowValidatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias TeslaMate.Import.{RejectedRow, RejectionReport, RowValidator}

  @valid_row %{
    "Date" => "2018-01-01 10:00:00",
    "vehicle_id" => "1111111111",
    "display_name" => "Resilient",
    "vin" => "1YYSA1YYYFF08YYYY",
    "id" => "42",
    "state" => "online",
    "latitude" => "51.5000",
    "longitude" => "-0.1200",
    "shift_state" => "D",
    "speed" => "10.5",
    "power" => "1",
    "odometer" => "1000.0",
    "battery_level" => "60",
    "usable_battery_level" => "60",
    "ideal_battery_range" => "200.0",
    "est_battery_range" => "195.0",
    "battery_range" => "198.0"
  }

  test "accepts a row with values used by the importer" do
    assert {:ok, %TeslaApi.Vehicle{}} = RowValidator.parse(@valid_row, "Etc/UTC")
  end

  test "reports invalid typed fields without retaining their values" do
    private_value = "PRIVATE_COORDINATE_SENTINEL"

    assert {:error, :invalid_fields, fields} =
             @valid_row
             |> Map.put("latitude", private_value)
             |> Map.put("longitude", "PRIVATE_LONGITUDE_SENTINEL")
             |> RowValidator.parse("Etc/UTC")

    assert "drive_state.latitude" in fields
    assert "drive_state.longitude" in fields
    refute inspect(fields) =~ private_value
  end

  test "reports an invalid date without retaining its value" do
    assert {:error, :invalid_date, ["Date"]} =
             @valid_row
             |> Map.put("Date", "PRIVATE_INVALID_DATE_SENTINEL")
             |> RowValidator.parse("Etc/UTC")
  end

  test "rejects invalid booleans instead of converting them to nil" do
    assert {:error, :invalid_fields, fields} =
             @valid_row
             |> Map.put("battery_heater_on", "PRIVATE_BOOLEAN_SENTINEL")
             |> RowValidator.parse("Etc/UTC")

    assert fields == ["charge_state.battery_heater_on"]
    refute inspect(fields) =~ "PRIVATE_BOOLEAN_SENTINEL"
  end

  test "accepts legacy numeric boolean flags" do
    assert {:ok, vehicle} =
             @valid_row
             |> Map.put("is_front_defroster_on", "3")
             |> RowValidator.parse("Etc/UTC")

    assert vehicle.climate_state.is_front_defroster_on
  end

  test "rejects ambiguous local timestamps" do
    assert {:error, :ambiguous_local_time, ["Date"]} =
             @valid_row
             |> Map.put("Date", "2018-10-28 02:30:00")
             |> RowValidator.parse("Europe/Berlin")
  end

  test "rejects nonexistent local timestamps" do
    assert {:error, :nonexistent_local_time, ["Date"]} =
             @valid_row
             |> Map.put("Date", "2018-03-25 02:30:00")
             |> RowValidator.parse("Europe/Berlin")
  end

  test "does not log unknown source values" do
    private_value = "PRIVATE_UNKNOWN_COLUMN_SENTINEL"
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log([level: :debug], fn ->
          assert {:ok, %TeslaApi.Vehicle{}} =
                   @valid_row
                   |> Map.put("unknown_column", private_value)
                   |> RowValidator.parse("Etc/UTC")
        end)
      after
        Logger.configure(level: previous_level)
      end

    assert log =~ "unknown_column"
    refute log =~ private_value
  end

  test "keeps exact totals while bounding report details" do
    report =
      Enum.reduce(1..105, %RejectionReport{}, fn row, report ->
        RejectionReport.record(
          report,
          RejectedRow.new("/private/import/TeslaFi12018.csv", row, :parse_error)
        )
      end)

    assert report.count == 105
    assert length(report.examples) == 100
    assert RejectionReport.truncated?(report)
    assert Enum.map(report.examples, & &1.row) == Enum.to_list(1..100)
  end

  test "rejected-row metadata contains no source values or directory path" do
    rejected =
      RejectedRow.new(
        "/private/import/TeslaFi12018.csv",
        3,
        :invalid_fields,
        ["drive_state.latitude"]
      )

    assert rejected.file == "TeslaFi12018.csv"
    refute inspect(rejected) =~ "/private/import"
    refute Map.has_key?(Map.from_struct(rejected), :raw_row)
  end

  test "bounds and normalizes invalid field names" do
    fields = Enum.map(12..1//-1, &"field.#{&1}") ++ ["field.1"]

    rejected =
      RejectedRow.new("TeslaFi12018.csv", 3, :invalid_fields, fields)

    assert length(rejected.fields) == 8
    assert rejected.fields == Enum.sort(rejected.fields)
    assert Enum.uniq(rejected.fields) == rejected.fields
  end
end
