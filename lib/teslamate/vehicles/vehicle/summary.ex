defmodule TeslaMate.Vehicles.Vehicle.Summary do
  import TeslaMate.Vehicles.Vehicle.Convert, only: [miles_to_km: 2, mph_to_kmh: 1]

  alias TeslaApi.Vehicle.State.{Drive, Charge}
  alias TeslaApi.Vehicle

  defstruct [
    :display_name,
    :state,
    :battery_level,
    :ideal_battery_range_km,
    :charge_energy_added,
    :speed,
    :outside_temp,
    :inside_temp,
    :locked,
    :sentry_mode
  ]

  def into(state, vehicle) do
    %__MODULE__{format_vehicle(vehicle) | state: format_state(state)}
  end

  defp format_state({:driving, _trip_id}), do: :driving
  defp format_state({:charging, "Starting", _process_id}), do: :charging
  defp format_state({:charging, "Charging", _process_id}), do: :charging
  defp format_state({:charging, "Complete", _process_id}), do: :charging_complete
  defp format_state({:updating, _update_id}), do: :updating
  defp format_state({:suspended, _}), do: :suspended
  defp format_state(state) when is_atom(state), do: state

  defp format_vehicle(%Vehicle{} = vehicle) do
    %__MODULE__{
      display_name: vehicle.display_name,
      speed: speed(vehicle),
      ideal_battery_range_km: range_km(vehicle),
      battery_level: get_in_struct(vehicle, [:charge_state, :battery_level]),
      charge_energy_added: get_in_struct(vehicle, [:charge_state, :charge_energy_added]),
      outside_temp: get_in_struct(vehicle, [:climate_state, :outside_temp]),
      inside_temp: get_in_struct(vehicle, [:climate_state, :inside_temp]),
      locked: get_in_struct(vehicle, [:vehicle_state, :locked]),
      sentry_mode: get_in_struct(vehicle, [:vehicle_state, :sentry_mode])
    }
  end

  defp range_km(%Vehicle{charge_state: %Charge{ideal_battery_range: r}}), do: miles_to_km(r, 1)
  defp range_km(_vehicle), do: nil

  defp speed(%Vehicle{drive_state: %Drive{speed: s}}) when not is_nil(s), do: mph_to_kmh(s)
  defp speed(_vehicle), do: nil

  defp get_in_struct(struct, keys) do
    Enum.reduce(keys, struct, fn key, acc -> if acc, do: Map.get(acc, key) end)
  end
end
