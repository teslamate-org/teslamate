defmodule TeslaMateWeb.Api.Views.ChargeJSON do
  alias TeslaMate.Log.{ChargingProcess, Charge}
  alias TeslaMate.Locations.{Address, GeoFence}

  def charging_process(%ChargingProcess{} = cp) do
    %{
      id: cp.id,
      car_id: cp.car_id,
      start_date: format_datetime(cp.start_date),
      end_date: format_datetime(cp.end_date),
      address: format_address(cp.address),
      geofence: format_geofence(cp.geofence),
      charge_energy_added: to_float(cp.charge_energy_added),
      charge_energy_used: to_float(cp.charge_energy_used),
      start_ideal_range_km: to_float(cp.start_ideal_range_km),
      end_ideal_range_km: to_float(cp.end_ideal_range_km),
      start_rated_range_km: to_float(cp.start_rated_range_km),
      end_rated_range_km: to_float(cp.end_rated_range_km),
      start_battery_level: cp.start_battery_level,
      end_battery_level: cp.end_battery_level,
      duration_min: cp.duration_min,
      outside_temp_avg: to_float(cp.outside_temp_avg),
      cost: to_float(cp.cost)
    }
  end

  def charging_process_detail(%ChargingProcess{} = cp) do
    charging_process(cp)
  end

  def charge(%Charge{} = c) do
    %{
      id: c.id,
      date: format_datetime(c.date),
      battery_level: c.battery_level,
      usable_battery_level: c.usable_battery_level,
      charge_energy_added: to_float(c.charge_energy_added),
      charger_actual_current: c.charger_actual_current,
      charger_phases: c.charger_phases,
      charger_pilot_current: c.charger_pilot_current,
      charger_power: c.charger_power,
      charger_voltage: c.charger_voltage,
      ideal_battery_range_km: to_float(c.ideal_battery_range_km),
      rated_battery_range_km: to_float(c.rated_battery_range_km),
      outside_temp: to_float(c.outside_temp),
      fast_charger_present: c.fast_charger_present,
      fast_charger_brand: c.fast_charger_brand,
      fast_charger_type: c.fast_charger_type,
      conn_charge_cable: c.conn_charge_cable
    }
  end

  defp format_address(%Address{} = a) do
    %{
      id: a.id,
      display_name: a.display_name,
      city: a.city,
      country: a.country,
      state: a.state
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
