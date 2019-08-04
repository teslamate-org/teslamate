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
    :sentry_mode,
    :plugged_in,
    :scheduled_charging_start_time,
    :charge_limit_soc
  ]

  def into(:start, nil) do
    %__MODULE__{state: :unavailable}
  end

  def into(state, vehicle) do
    %__MODULE__{format_vehicle(vehicle) | state: format_state(state)}
  end

  defp format_state({:charging, "Starting", _process_id}), do: :charging
  defp format_state({:charging, "Charging", _process_id}), do: :charging
  defp format_state({:charging, "Complete", _process_id}), do: :charging_complete
  defp format_state({state, _}) when is_atom(state), do: state
  defp format_state(state) when is_atom(state), do: state

  defp format_vehicle(%Vehicle{} = vehicle) do
    %__MODULE__{
      display_name: vehicle.display_name,
      speed: speed(vehicle),
      ideal_battery_range_km: range_km(vehicle),
      battery_level: get_in_struct(vehicle, [:charge_state, :battery_level]),
      charge_energy_added: get_in_struct(vehicle, [:charge_state, :charge_energy_added]),
      plugged_in: plugged_in(vehicle),
      scheduled_charging_start_time:
        get_in_struct(vehicle, [:charge_state, :scheduled_charging_start_time]) |> to_datetime(),
      charge_limit_soc: get_in_struct(vehicle, [:charge_state, :charge_limit_soc]),
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

  defp plugged_in(%Vehicle{charge_state: nil}), do: nil

  defp plugged_in(%Vehicle{
         charge_state: %Charge{charge_port_latch: "Engaged", charge_port_door_open: true}
       }) do
    true
  end

  defp plugged_in(_vehicle), do: false

  defp to_datetime(nil), do: nil
  defp to_datetime(ts), do: DateTime.from_unix!(ts)

  defp get_in_struct(struct, keys) do
    Enum.reduce(keys, struct, fn key, acc -> if acc, do: Map.get(acc, key) end)
  end
end
