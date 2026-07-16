defmodule TeslaMate.Vehicles.Vehicle.DataQualityTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Stream
  alias TeslaApi.Vehicle
  alias TeslaApi.Vehicle.State.{Charge, Climate, Drive, VehicleConfig, VehicleState}
  alias TeslaMate.Log
  alias TeslaMate.Vehicles.Vehicle.{DataQuality, Summary}

  test "keeps confidence, freshness, availability and source independent" do
    now = DateTime.utc_now()
    timestamp = DateTime.to_unix(now, :millisecond)

    vehicle = %Vehicle{
      display_name: "Blue Thunder",
      drive_state: %Drive{timestamp: timestamp, latitude: 51.5},
      charge_state: %Charge{
        timestamp: timestamp,
        battery_level: 80,
        est_battery_range: 200,
        charging_state: "Disconnected"
      },
      climate_state: %Climate{timestamp: timestamp},
      vehicle_state: %VehicleState{timestamp: timestamp, locked: true},
      vehicle_config: %VehicleConfig{timestamp: timestamp}
    }

    summary = %Summary{
      latitude: 51.5,
      battery_level: 80,
      est_battery_range_km: 321.87,
      plugged_in: false,
      locked: true
    }

    quality =
      summary
      |> DataQuality.for_summary(DataQuality.from_rest(vehicle, now), %{car: nil}, now)

    assert %DataQuality{
             confidence: :exact,
             freshness: :fresh,
             availability: :available,
             source: :tesla_rest,
             reason: nil
           } = quality.latitude

    assert DateTime.to_unix(quality.latitude.observed_at, :millisecond) == timestamp

    assert %DataQuality{confidence: :estimated, reason: :tesla_estimate} =
             quality.est_battery_range_km

    assert %DataQuality{confidence: :derived, source: :teslamate_derived} = quality.plugged_in

    assert %DataQuality{availability: :unavailable, reason: :not_reported} =
             quality.inside_temp

    assert map_size(quality) == map_size(Map.from_struct(summary)) - 2
  end

  test "stream observations replace only fields merged from the stream" do
    now = DateTime.utc_now()
    timestamp = DateTime.to_unix(now, :millisecond)

    vehicle = %Vehicle{
      drive_state: %Drive{timestamp: timestamp},
      charge_state: %Charge{timestamp: timestamp},
      climate_state: %Climate{timestamp: timestamp},
      vehicle_state: %VehicleState{timestamp: timestamp},
      vehicle_config: %VehicleConfig{timestamp: timestamp}
    }

    stream_time = DateTime.add(now, 10, :second)

    stream_data = %Stream.Data{
      time: stream_time,
      est_lat: 91,
      est_lng: 10,
      speed: 20,
      power: 5,
      est_heading: 180,
      shift_state: "D",
      soc: 101,
      odometer: 100,
      elevation: 12
    }

    quality =
      DataQuality.from_rest(vehicle, now)
      |> DataQuality.merge_stream(stream_data, stream_time)

    summary = %Summary{
      latitude: 91,
      active_route_latitude: 91,
      active_route_longitude: -181,
      battery_level: 101,
      locked: true,
      elevation: 12
    }

    quality = DataQuality.for_summary(summary, quality, %{car: nil}, stream_time)

    assert %DataQuality{
             source: :tesla_stream,
             observed_at: ^stream_time,
             availability: :corrupted,
             reason: :outside_expected_range
           } = quality.latitude

    assert %DataQuality{source: :tesla_stream, availability: :corrupted} =
             quality.battery_level

    assert %DataQuality{source: :tesla_stream, availability: :available} = quality.elevation
    assert %DataQuality{source: :tesla_rest, availability: :available} = quality.locked

    assert %DataQuality{availability: :corrupted, reason: :outside_expected_range} =
             quality.active_route_latitude

    assert %DataQuality{availability: :corrupted, reason: :outside_expected_range} =
             quality.active_route_longitude
  end

  test "restored values remain explicitly stale and unknown values remain unavailable" do
    observed_at = DateTime.add(DateTime.utc_now(), -3600, :second)
    version_observed_at = DateTime.add(observed_at, -3600, :second)
    position = %Log.Position{date: observed_at}

    vehicle = %Vehicle{
      display_name: "Blue Thunder",
      vehicle_state: %VehicleState{car_version: "2026.20 abc123"}
    }

    summary = %Summary{
      latitude: 51.5,
      est_battery_range_km: 300,
      shift_state: :unknown,
      charge_energy_added: :unknown,
      version: "2026.20"
    }

    quality =
      position
      |> DataQuality.from_restored_position(vehicle,
        version_observed_at: version_observed_at
      )
      |> then(&DataQuality.for_summary(summary, &1, %{car: nil}, DateTime.utc_now()))

    assert %DataQuality{
             confidence: :exact,
             freshness: :stale,
             availability: :available,
             source: :teslamate_database,
             observed_at: ^observed_at,
             reason: :restored_last_position
           } = quality.latitude

    assert %DataQuality{confidence: :estimated, freshness: :stale} =
             quality.est_battery_range_km

    assert %DataQuality{
             availability: :unavailable,
             confidence: :unknown,
             source: :unknown,
             reason: :unknown_value
           } =
             quality.shift_state

    assert %DataQuality{availability: :unavailable, source: :unknown} =
             quality.charge_energy_added

    assert %DataQuality{
             confidence: :derived,
             freshness: :stale,
             source: :teslamate_derived,
             observed_at: ^version_observed_at,
             reason: :restored_last_update
           } = quality.version
  end

  test "public payload contains metadata but never field values" do
    now = DateTime.utc_now()

    quality = %{
      display_name: %DataQuality{
        confidence: :exact,
        freshness: :fresh,
        availability: :available,
        source: :tesla_rest,
        observed_at: now,
        reason: nil
      }
    }

    payload = DataQuality.public_payload(quality, now)
    encoded = Jason.encode!(payload)

    assert payload.fields["display_name"].age_seconds == 0
    assert payload.fields["display_name"].label == "exact"
    refute encoded =~ "Blue Thunder"
    refute encoded =~ "\"value\""
  end

  test "MQTT groups identical metadata and uses minute precision for stable deduplication" do
    first = ~U[2026-07-16 10:00:05Z]
    second = ~U[2026-07-16 10:00:55Z]

    quality = fn observed_at ->
      %{
        heading: %DataQuality{
          confidence: :exact,
          freshness: :fresh,
          availability: :available,
          source: :tesla_stream,
          observed_at: observed_at,
          reason: nil
        },
        speed: %DataQuality{
          confidence: :exact,
          freshness: :fresh,
          availability: :available,
          source: :tesla_stream,
          observed_at: observed_at,
          reason: nil
        }
      }
    end

    assert DataQuality.mqtt_payload(quality.(first)) == DataQuality.mqtt_payload(quality.(second))

    assert %{
             "groups" => [
               %{
                 "fields" => ["heading", "speed"],
                 "observed_at" => "2026-07-16T10:00:00Z"
               }
             ]
           } = Jason.decode!(DataQuality.mqtt_payload(quality.(first)))

    refute DataQuality.mqtt_payload(quality.(second)) ==
             DataQuality.mqtt_payload(quality.(~U[2026-07-16 10:01:00Z]))
  end

  test "MQTT grouped metadata stays below the 4 KiB payload ceiling" do
    observed_at = ~U[2026-07-16 10:00:05Z]

    reasons =
      [nil, :derived_value, :terrain_lookup, :tesla_estimate, :unknown_value, :not_reported]

    quality =
      %Summary{}
      |> Map.from_struct()
      |> Map.drop([:car, :quality])
      |> Map.keys()
      |> Enum.sort()
      |> Enum.with_index()
      |> Map.new(fn {field, index} ->
        {field,
         %DataQuality{
           confidence: :exact,
           freshness: :fresh,
           availability: :available,
           source: :tesla_rest,
           observed_at: observed_at,
           reason: Enum.at(reasons, rem(index, length(reasons)))
         }}
      end)

    payload = DataQuality.mqtt_payload(quality)
    %{"groups" => groups} = Jason.decode!(payload)

    assert length(groups) == length(reasons)
    assert Enum.sum(Enum.map(groups, &length(&1["fields"]))) == map_size(quality)
    assert byte_size(payload) < 4_096
  end
end
