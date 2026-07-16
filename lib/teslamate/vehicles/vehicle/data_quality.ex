defmodule TeslaMate.Vehicles.Vehicle.DataQuality do
  @moduledoc """
  Describes where a live summary field came from and how much it can be trusted.

  Quality is kept separately from field values so existing consumers keep receiving
  exactly the same payloads.
  """

  alias TeslaApi.Stream
  alias TeslaApi.Vehicle
  alias TeslaMate.Log

  @stale_after_seconds 300

  @type confidence :: :exact | :derived | :estimated | :unknown
  @type freshness :: :fresh | :stale | :unknown
  @type availability :: :available | :corrupted | :unavailable
  @type source ::
          :tesla_rest | :tesla_stream | :teslamate_database | :teslamate_derived | :unknown

  @type t :: %__MODULE__{
          confidence: confidence(),
          freshness: freshness(),
          availability: availability(),
          source: source(),
          observed_at: DateTime.t() | nil,
          reason: atom() | nil
        }

  defstruct confidence: :unknown,
            freshness: :unknown,
            availability: :unavailable,
            source: :unknown,
            observed_at: nil,
            reason: :not_reported

  @drive_fields ~w(
    active_route_destination active_route_latitude active_route_longitude
    active_route_energy_at_arrival active_route_miles_to_arrival
    active_route_minutes_to_arrival active_route_traffic_minutes_delay
    latitude longitude power speed shift_state heading
  )a

  @charge_fields ~w(
    battery_level charging_state usable_battery_level ideal_battery_range_km
    est_battery_range_km rated_battery_range_km charge_energy_added
    scheduled_charging_start_time charge_limit_soc charger_power plugged_in
    charge_port_door_open time_to_full_charge charger_phases charger_actual_current
    charger_voltage charge_current_request charge_current_request_max
  )a

  @climate_fields ~w(
    outside_temp inside_temp is_climate_on is_preconditioning climate_keeper_mode
  )a

  @vehicle_state_fields ~w(
    locked sentry_mode windows_open driver_front_window_open driver_rear_window_open
    passenger_front_window_open passenger_rear_window_open doors_open
    driver_front_door_open driver_rear_door_open passenger_front_door_open
    passenger_rear_door_open odometer version update_available update_version
    update_status is_user_present trunk_open frunk_open tpms_pressure_fl
    tpms_pressure_fr tpms_pressure_rl tpms_pressure_rr tpms_soft_warning_fl
    tpms_soft_warning_fr tpms_soft_warning_rl tpms_soft_warning_rr
    center_display_state service_mode sun_roof_state sun_roof_percent_open
    download_perc install_perc
  )a

  @vehicle_config_fields ~w(sun_roof_installed)a
  @database_fields ~w(model trim_badging exterior_color wheel_type spoiler_type)a

  @derived_fields ~w(
    plugged_in windows_open driver_front_window_open driver_rear_window_open
    passenger_front_window_open passenger_rear_window_open doors_open
    driver_front_door_open driver_rear_door_open passenger_front_door_open
    passenger_rear_door_open trunk_open frunk_open version update_available
    update_version sun_roof_installed
  )a

  @restored_position_fields ~w(
    latitude longitude battery_level usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km
    outside_temp inside_temp odometer
  )a

  @stream_fields ~w(latitude longitude speed power heading shift_state battery_level odometer)a

  @percentage_fields ~w(
    battery_level usable_battery_level charge_limit_soc download_perc install_perc
    sun_roof_percent_open
  )a

  @non_negative_fields ~w(
    odometer ideal_battery_range_km est_battery_range_km rated_battery_range_km
  )a

  @spec from_rest(%Vehicle{}, DateTime.t()) :: %{atom() => t()}
  def from_rest(%Vehicle{} = vehicle, received_at \\ DateTime.utc_now()) do
    %{}
    |> put_fields(@drive_fields, rest_quality(vehicle.drive_state, received_at))
    |> put_fields(@charge_fields, rest_quality(vehicle.charge_state, received_at))
    |> put_fields(@climate_fields, rest_quality(vehicle.climate_state, received_at))
    |> put_fields(@vehicle_state_fields, rest_quality(vehicle.vehicle_state, received_at))
    |> put_fields(@vehicle_config_fields, rest_quality(vehicle.vehicle_config, received_at))
    |> Map.put(:display_name, rest_quality(vehicle.vehicle_state, received_at))
  end

  @spec from_restored_position(%Log.Position{}, %Vehicle{}, keyword()) :: %{atom() => t()}
  def from_restored_position(
        %Log.Position{date: observed_at},
        %Vehicle{} = vehicle,
        opts \\ []
      ) do
    received_at = Keyword.get_lazy(opts, :received_at, &DateTime.utc_now/0)
    version_observed_at = Keyword.get(opts, :version_observed_at)

    restored = %__MODULE__{
      confidence: :exact,
      freshness: :stale,
      availability: :available,
      source: :teslamate_database,
      observed_at: normalize_datetime(observed_at),
      reason: :restored_last_position
    }

    %{}
    |> put_fields(@restored_position_fields, restored)
    |> put_restored_version(vehicle, version_observed_at)
    |> Map.put(:display_name, rest_quality(vehicle.vehicle_state, received_at))
  end

  @spec merge_stream(%{atom() => t()}, %Stream.Data{}, DateTime.t()) :: %{atom() => t()}
  def merge_stream(quality, %Stream.Data{} = stream_data, received_at \\ DateTime.utc_now()) do
    observed_at = normalize_datetime(stream_data.time) || received_at

    stream_quality = %__MODULE__{
      confidence: :exact,
      freshness: :fresh,
      availability: :available,
      source: :tesla_stream,
      observed_at: observed_at,
      reason: nil
    }

    quality
    |> put_fields(@stream_fields, stream_quality)
    |> Map.put(:elevation, stream_quality)
  end

  @spec for_summary(struct(), %{atom() => t()}, map(), DateTime.t()) :: %{atom() => t()}
  def for_summary(summary, quality, attrs, now \\ DateTime.utc_now()) do
    quality =
      quality
      |> put_internal_fields()
      |> put_database_fields(attrs[:car])
      |> put_derived_fields()
      |> put_geofence(summary)
      |> put_elevation(summary)

    summary
    |> Map.from_struct()
    |> Map.drop([:car, :quality])
    |> Enum.reduce(%{}, fn {field, value}, acc ->
      field_quality = quality |> Map.get(field, %__MODULE__{}) |> classify(field, value, now)
      Map.put(acc, field, field_quality)
    end)
  end

  @spec public_payload(%{atom() => t()}, DateTime.t()) :: map()
  def public_payload(quality, now \\ DateTime.utc_now()) do
    fields =
      quality
      |> Enum.sort_by(fn {field, _quality} -> field end)
      |> Map.new(fn {field, field_quality} ->
        {Atom.to_string(field), metadata(field_quality, now, include_age: true)}
      end)

    %{
      schema_version: 1,
      generated_at: DateTime.to_iso8601(now),
      fields: fields
    }
  end

  @spec mqtt_payload(%{atom() => t()}) :: String.t() | nil
  def mqtt_payload(quality) when map_size(quality) == 0, do: nil

  def mqtt_payload(quality) do
    groups =
      quality
      |> Enum.sort_by(fn {field, _quality} -> field end)
      |> Enum.map(fn {field, field_quality} ->
        field_quality = %{
          field_quality
          | observed_at: mqtt_observed_at(field_quality.observed_at)
        }

        {
          metadata(field_quality, field_quality.observed_at || DateTime.utc_now(),
            include_age: false
          ),
          Atom.to_string(field)
        }
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {metadata, fields} -> Map.put(metadata, :fields, Enum.sort(fields)) end)
      |> Enum.sort_by(fn %{fields: fields} -> hd(fields) end)

    Jason.encode!(%{schema_version: 1, groups: groups})
  end

  defp put_internal_fields(quality) do
    internal = %__MODULE__{
      confidence: :derived,
      freshness: :fresh,
      availability: :available,
      source: :teslamate_derived,
      observed_at: nil,
      reason: :derived_value
    }

    put_fields(quality, [:state, :since, :healthy], internal)
  end

  defp put_database_fields(quality, car) do
    observed_at =
      case car do
        %{updated_at: updated_at} -> normalize_datetime(updated_at)
        _ -> nil
      end

    database = %__MODULE__{
      confidence: :exact,
      freshness: :unknown,
      availability: :available,
      source: :teslamate_database,
      observed_at: observed_at,
      reason: nil
    }

    put_fields(quality, @database_fields, database)
  end

  defp put_derived_fields(quality) do
    Enum.reduce(@derived_fields, quality, fn field, acc ->
      base = Map.get(acc, field, %__MODULE__{})

      Map.put(acc, field, %{
        base
        | confidence: :derived,
          source: :teslamate_derived,
          reason: provenance_reason(base, :derived_value)
      })
    end)
  end

  defp put_geofence(quality, summary) do
    base = Map.get(quality, :latitude, %__MODULE__{})

    Map.put(quality, :geofence, %{
      base
      | confidence: :derived,
        source: :teslamate_derived,
        reason: provenance_reason(base, :derived_value),
        availability: if(summary.geofence, do: :available, else: :unavailable)
    })
  end

  defp put_elevation(quality, summary) do
    if Map.has_key?(quality, :elevation) do
      quality
    else
      base = Map.get(quality, :latitude, %__MODULE__{})

      Map.put(quality, :elevation, %{
        base
        | confidence: :estimated,
          source: :teslamate_derived,
          reason: :terrain_lookup,
          availability: if(is_nil(summary.elevation), do: :unavailable, else: :available)
      })
    end
  end

  defp rest_quality(nil, received_at) do
    %__MODULE__{
      confidence: :exact,
      freshness: :fresh,
      availability: :unavailable,
      source: :tesla_rest,
      observed_at: received_at,
      reason: :not_reported
    }
  end

  defp rest_quality(group, received_at) do
    observed_at = normalize_datetime(Map.get(group, :timestamp)) || received_at

    %__MODULE__{
      confidence: :exact,
      freshness: :fresh,
      availability: :available,
      source: :tesla_rest,
      observed_at: observed_at,
      reason: nil
    }
  end

  defp put_fields(quality, fields, field_quality) do
    Enum.reduce(fields, quality, &Map.put(&2, &1, field_quality))
  end

  defp classify(field_quality, _field, nil, now) do
    %{refresh(field_quality, now) | availability: :unavailable, reason: :not_reported}
  end

  defp classify(field_quality, _field, :unknown, now) do
    %{refresh(field_quality, now) | availability: :unavailable, reason: :unknown_value}
  end

  defp classify(field_quality, field, value, now) do
    field_quality = clear_unavailable_reason(field_quality)

    field_quality =
      if field == :est_battery_range_km do
        %{
          field_quality
          | confidence: :estimated,
            reason: field_quality.reason || :tesla_estimate
        }
      else
        field_quality
      end

    case corrupted_reason(field, value) do
      nil -> %{refresh(field_quality, now) | availability: :available}
      reason -> %{refresh(field_quality, now) | availability: :corrupted, reason: reason}
    end
  end

  defp corrupted_reason(field, value) when field in @percentage_fields do
    if number_in_range?(value, 0, 100), do: nil, else: :outside_expected_range
  end

  defp corrupted_reason(field, value) when field in [:latitude, :active_route_latitude] do
    if number_in_range?(value, -90, 90), do: nil, else: :outside_expected_range
  end

  defp corrupted_reason(field, value) when field in [:longitude, :active_route_longitude] do
    if number_in_range?(value, -180, 180), do: nil, else: :outside_expected_range
  end

  defp corrupted_reason(field, value) when field in @non_negative_fields do
    if number_in_range?(value, 0, :infinity), do: nil, else: :outside_expected_range
  end

  defp corrupted_reason(_field, _value), do: nil

  defp provenance_reason(%__MODULE__{reason: reason}, fallback)
       when reason in [nil, :not_reported, :unknown_value],
       do: fallback

  defp provenance_reason(%__MODULE__{reason: reason}, _fallback), do: reason

  defp clear_unavailable_reason(%__MODULE__{reason: reason} = quality)
       when reason in [:not_reported, :unknown_value],
       do: %{quality | reason: nil}

  defp clear_unavailable_reason(quality), do: quality

  defp number_in_range?(%Decimal{} = value, min, max) do
    number_in_range?(Decimal.to_float(value), min, max)
  end

  defp number_in_range?(value, min, :infinity) when is_number(value), do: value >= min
  defp number_in_range?(value, min, max) when is_number(value), do: value >= min and value <= max
  defp number_in_range?(_value, _min, _max), do: false

  defp refresh(
         %__MODULE__{freshness: :fresh, observed_at: %DateTime{} = observed_at} = quality,
         now
       ) do
    if DateTime.diff(now, observed_at) > @stale_after_seconds do
      %{quality | freshness: :stale}
    else
      quality
    end
  end

  defp refresh(quality, _now), do: quality

  defp metadata(%__MODULE__{} = quality, now, opts) do
    quality = if Keyword.fetch!(opts, :include_age), do: refresh(quality, now), else: quality

    %{
      label: label(quality),
      confidence: Atom.to_string(quality.confidence),
      freshness: Atom.to_string(quality.freshness),
      availability: Atom.to_string(quality.availability),
      source: Atom.to_string(quality.source),
      observed_at: iso8601(quality.observed_at),
      reason: quality.reason && Atom.to_string(quality.reason)
    }
    |> maybe_put_age(quality, now, opts)
  end

  defp maybe_put_age(metadata, quality, now, include_age: true) do
    age_seconds =
      case quality.observed_at do
        %DateTime{} = observed_at -> max(DateTime.diff(now, observed_at), 0)
        nil -> nil
      end

    Map.put(metadata, :age_seconds, age_seconds)
  end

  defp maybe_put_age(metadata, _quality, _now, include_age: false), do: metadata

  defp label(%__MODULE__{availability: :corrupted}), do: "corrupted"
  defp label(%__MODULE__{availability: :unavailable}), do: "unavailable"
  defp label(%__MODULE__{freshness: :stale}), do: "stale"
  defp label(%__MODULE__{confidence: confidence}), do: Atom.to_string(confidence)

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    DateTime.from_naive!(datetime, "Etc/UTC")
  end

  defp normalize_datetime(timestamp) when is_integer(timestamp) and timestamp > 0 do
    unit = if abs(timestamp) > 10_000_000_000, do: :millisecond, else: :second

    case DateTime.from_unix(timestamp, unit) do
      {:ok, datetime} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp normalize_datetime(timestamp) when is_integer(timestamp), do: nil

  defp normalize_datetime(_datetime), do: nil

  defp put_restored_version(
         quality,
         %Vehicle{vehicle_state: %{car_version: version}},
         observed_at
       )
       when is_binary(version) and version != "" do
    Map.put(quality, :version, %__MODULE__{
      confidence: :exact,
      freshness: :stale,
      availability: :available,
      source: :teslamate_database,
      observed_at: normalize_datetime(observed_at),
      reason: :restored_last_update
    })
  end

  defp put_restored_version(quality, _vehicle, _observed_at), do: quality

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(nil), do: nil

  defp mqtt_observed_at(%DateTime{} = datetime) do
    %{datetime | second: 0, microsecond: {0, 0}}
  end

  defp mqtt_observed_at(nil), do: nil
end
