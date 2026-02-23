defmodule TeslaMateWeb.Api.Views.DriveJSON do
  alias TeslaMate.Log.{Drive, Position}
  alias TeslaMate.Locations.{Address, GeoFence}

  def drive(%Drive{} = d) do
    %{
      id: d.id,
      car_id: d.car_id,
      start_date: format_datetime(d.start_date),
      end_date: format_datetime(d.end_date),
      start_address: format_address(d.start_address),
      end_address: format_address(d.end_address),
      start_geofence: format_geofence(d.start_geofence),
      end_geofence: format_geofence(d.end_geofence),
      distance: to_float(d.distance),
      duration_min: d.duration_min,
      speed_max: d.speed_max,
      power_max: d.power_max,
      power_min: d.power_min,
      start_km: to_float(d.start_km),
      end_km: to_float(d.end_km),
      start_ideal_range_km: to_float(d.start_ideal_range_km),
      end_ideal_range_km: to_float(d.end_ideal_range_km),
      start_rated_range_km: to_float(d.start_rated_range_km),
      end_rated_range_km: to_float(d.end_rated_range_km),
      outside_temp_avg: to_float(d.outside_temp_avg),
      inside_temp_avg: to_float(d.inside_temp_avg),
      ascent: d.ascent,
      descent: d.descent
    }
  end

  def drive_detail(%Drive{} = d) do
    drive(d)
  end

  def position(%Position{} = p) do
    %{
      id: p.id,
      date: format_datetime(p.date),
      latitude: to_float(p.latitude),
      longitude: to_float(p.longitude),
      elevation: p.elevation,
      speed: p.speed,
      power: p.power,
      odometer: to_float(p.odometer),
      battery_level: p.battery_level,
      ideal_battery_range_km: to_float(p.ideal_battery_range_km),
      rated_battery_range_km: to_float(p.rated_battery_range_km),
      outside_temp: to_float(p.outside_temp),
      inside_temp: to_float(p.inside_temp)
    }
  end

  defp format_address(%Address{} = a) do
    %{
      id: a.id,
      display_name: a.display_name,
      city: a.city,
      county: a.county,
      country: a.country,
      state: a.state,
      road: a.road,
      house_number: a.house_number
    }
  end

  defp format_address(_), do: nil

  defp format_geofence(%GeoFence{} = g) do
    %{id: g.id, name: g.name}
  end

  defp format_geofence(_), do: nil

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(v), do: v

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
