defmodule TeslaMate.Import.RowValidator do
  @moduledoc false

  alias TeslaMate.Import.LineParser

  @field_types [
    {[:id], :integer},
    {[:vehicle_id], :castable_integer},
    {[:vin], :string},
    {[:state], :string},
    {[:display_name], :string},
    {[:vehicle_config, :car_type], :string},
    {[:vehicle_config, :trim_badging], :string},
    {[:vehicle_config, :exterior_color], :string},
    {[:vehicle_config, :wheel_type], :string},
    {[:vehicle_config, :spoiler_type], :string},
    {[:drive_state, :timestamp], :integer},
    {[:drive_state, :latitude], :number},
    {[:drive_state, :longitude], :number},
    {[:drive_state, :speed], :number},
    {[:drive_state, :power], :integer},
    {[:drive_state, :shift_state], :string},
    {[:charge_state, :timestamp], :integer},
    {[:charge_state, :battery_level], :integer},
    {[:charge_state, :usable_battery_level], :integer},
    {[:charge_state, :battery_range], :number},
    {[:charge_state, :ideal_battery_range], :number},
    {[:charge_state, :est_battery_range], :number},
    {[:charge_state, :charge_energy_added], :number},
    {[:charge_state, :charger_actual_current], :integer},
    {[:charge_state, :charger_phases], :integer},
    {[:charge_state, :charger_pilot_current], :integer},
    {[:charge_state, :charger_power], :integer},
    {[:charge_state, :charger_voltage], :integer},
    {[:charge_state, :conn_charge_cable], :string},
    {[:charge_state, :fast_charger_brand], :string},
    {[:charge_state, :fast_charger_type], :string},
    {[:charge_state, :charging_state], :string},
    {[:charge_state, :battery_heater_on], :boolean},
    {[:charge_state, :fast_charger_present], :boolean},
    {[:charge_state, :not_enough_power_to_heat], :boolean},
    {[:climate_state, :timestamp], :integer},
    {[:climate_state, :outside_temp], :number},
    {[:climate_state, :inside_temp], :number},
    {[:climate_state, :fan_status], :integer},
    {[:climate_state, :driver_temp_setting], :number},
    {[:climate_state, :passenger_temp_setting], :number},
    {[:climate_state, :battery_heater], :boolean},
    {[:climate_state, :battery_heater_no_power], :boolean},
    {[:climate_state, :is_climate_on], :boolean},
    {[:climate_state, :is_rear_defroster_on], :boolean},
    {[:climate_state, :is_front_defroster_on], :boolean},
    {[:vehicle_state, :timestamp], :integer},
    {[:vehicle_state, :odometer], :number},
    {[:vehicle_state, :tpms_pressure_fl], :number},
    {[:vehicle_state, :tpms_pressure_fr], :number},
    {[:vehicle_state, :tpms_pressure_rl], :number},
    {[:vehicle_state, :tpms_pressure_rr], :number}
  ]

  def parse(row, timezone) when is_map(row) do
    with {:ok, timestamp} <- LineParser.parse_timestamp(Map.get(row, "Date"), timezone) do
      vehicle = LineParser.parse(row, timezone, timestamp)

      case invalid_fields(vehicle) do
        [] -> {:ok, vehicle}
        fields -> {:error, :invalid_fields, fields}
      end
    else
      {:error, reason} -> {:error, reason, ["Date"]}
    end
  rescue
    _error in [
      ArgumentError,
      ArithmeticError,
      BadMapError,
      FunctionClauseError,
      KeyError,
      MatchError
    ] ->
      {:error, :parse_error, []}
  end

  defp invalid_fields(vehicle) do
    @field_types
    |> Enum.reject(fn {path, type} -> valid_value?(type, value_at(vehicle, path)) end)
    |> Enum.map(fn {path, _type} -> Enum.join(path, ".") end)
  end

  defp value_at(value, []), do: value
  defp value_at(nil, _path), do: nil
  defp value_at(value, [key | path]) when is_map(value), do: value_at(Map.get(value, key), path)
  defp value_at(_value, _path), do: nil

  defp valid_value?(_type, nil), do: true
  defp valid_value?(:integer, value), do: is_integer(value)
  defp valid_value?(:number, value), do: is_number(value) or match?(%Decimal{}, value)
  defp valid_value?(:boolean, value), do: is_boolean(value)
  defp valid_value?(:string, value), do: is_binary(value)

  defp valid_value?(:castable_integer, value) do
    match?({:ok, _integer}, Ecto.Type.cast(:integer, value))
  end
end
