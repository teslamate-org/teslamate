defmodule TeslaMateWeb.Api.Views.PositionJSON do
  alias TeslaMate.Log.Position

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
      usable_battery_level: p.usable_battery_level,
      ideal_battery_range_km: to_float(p.ideal_battery_range_km),
      est_battery_range_km: to_float(p.est_battery_range_km),
      rated_battery_range_km: to_float(p.rated_battery_range_km),
      outside_temp: to_float(p.outside_temp),
      inside_temp: to_float(p.inside_temp),
      fan_status: p.fan_status,
      is_climate_on: p.is_climate_on
    }
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(v), do: v

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
