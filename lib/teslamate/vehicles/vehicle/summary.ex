defmodule TeslaMate.Vehicles.Vehicle.Summary do
  import TeslaMate.Convert, only: [miles_to_km: 2, mph_to_kmh: 1]

  alias TeslaApi.Vehicle.State.{Drive, Charge, VehicleState}
  alias TeslaApi.Vehicle
  alias TeslaMate.Log.Car

  defstruct ~w(
    car display_name state since healthy latitude longitude heading battery_level usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km charge_energy_added
    speed outside_temp inside_temp is_climate_on is_preconditioning locked sentry_mode
    plugged_in scheduled_charging_start_time charge_limit_soc charger_power windows_open doors_open
    odometer shift_state charge_port_door_open time_to_full_charge charger_phases
    charger_actual_current charger_voltage version update_available update_version is_user_present geofence
    model trim_badging exterior_color wheel_type spoiler_type trunk_open frunk_open elevation power
    charge_current_request charge_current_request_max tpms_pressure_fl tpms_pressure_fr tpms_pressure_rl tpms_pressure_rr
  )a

  def into(nil, %{state: :start, healthy?: healthy?, car: car}) do
    %__MODULE__{
      state: :unavailable,
      healthy: healthy?,
      trim_badging: get_car_attr(car, :trim_badging),
      exterior_color: get_car_attr(car, :exterior_color),
      spoiler_type: get_car_attr(car, :spoiler_type),
      wheel_type: get_car_attr(car, :wheel_type),
      model: get_car_attr(car, :model),
      car: car
    }
  end

  def into(vehicle, attrs) do
    %{
      state: state,
      since: since,
      healthy?: healthy?,
      car: car,
      elevation: elevation,
      geofence: gf
    } = attrs

    %__MODULE__{
      format_vehicle(vehicle)
      | state: format_state(state),
        since: since,
        healthy: healthy?,
        elevation: elevation,
        geofence: gf,
        trim_badging: get_car_attr(car, :trim_badging),
        exterior_color: get_car_attr(car, :exterior_color),
        spoiler_type: get_car_attr(car, :spoiler_type),
        wheel_type: get_car_attr(car, :wheel_type),
        model: get_car_attr(car, :model),
        car: car
    }
  end

  defp format_state({:driving, {:offline, _}, _id}), do: :offline
  defp format_state({:driving, _state, _id}), do: :driving
  defp format_state({state, _, _}) when is_atom(state), do: state
  defp format_state({state, _}) when is_atom(state), do: state
  defp format_state(state) when is_atom(state), do: state

  defp get_car_attr(%Car{exterior_color: v}, :exterior_color), do: v
  defp get_car_attr(%Car{spoiler_type: v}, :spoiler_type), do: v
  defp get_car_attr(%Car{trim_badging: v}, :trim_badging), do: v
  defp get_car_attr(%Car{wheel_type: v}, :wheel_type), do: v
  defp get_car_attr(%Car{model: v}, :model), do: v
  defp get_car_attr(nil, _key), do: nil

  defp format_vehicle(%Vehicle{} = vehicle) do
    %__MODULE__{
      # General
      display_name: vehicle.display_name,

      # Drive State
      latitude: get_in_struct(vehicle, [:drive_state, :latitude]),
      longitude: get_in_struct(vehicle, [:drive_state, :longitude]),
      power: get_in_struct(vehicle, [:drive_state, :power]),
      speed: speed(vehicle),
      shift_state: get_in_struct(vehicle, [:drive_state, :shift_state]),
      heading: get_in_struct(vehicle, [:drive_state, :heading]),

      # Charge State
      battery_level: charge(vehicle, :battery_level),
      charge_current_request: charge(vehicle, :charge_current_request),
      charge_current_request_max: charge(vehicle, :charge_current_request_max),
      charge_energy_added: charge(vehicle, :charge_energy_added),
      charge_limit_soc: charge(vehicle, :charge_limit_soc),
      charge_port_door_open: charge(vehicle, :charge_port_door_open),
      charger_actual_current: charge(vehicle, :charger_actual_current),
      charger_phases: charge(vehicle, :charger_phases),
      charger_power: charge(vehicle, :charger_power),
      charger_voltage: charge(vehicle, :charger_voltage),
      est_battery_range_km: charge(vehicle, :est_battery_range) |> miles_to_km(2),
      ideal_battery_range_km: charge(vehicle, :ideal_battery_range) |> miles_to_km(2),
      plugged_in: plugged_in(vehicle),
      rated_battery_range_km: charge(vehicle, :battery_range) |> miles_to_km(2),
      scheduled_charging_start_time:
        charge(vehicle, :scheduled_charging_start_time) |> to_datetime(),
      time_to_full_charge: charge(vehicle, :time_to_full_charge),
      usable_battery_level: charge(vehicle, :usable_battery_level),

      # Climate State
      is_climate_on: get_in_struct(vehicle, [:climate_state, :is_climate_on]),
      is_preconditioning: get_in_struct(vehicle, [:climate_state, :is_preconditioning]),
      outside_temp: get_in_struct(vehicle, [:climate_state, :outside_temp]),
      inside_temp: get_in_struct(vehicle, [:climate_state, :inside_temp]),

      # Vehicle State
      odometer: get_in_struct(vehicle, [:vehicle_state, :odometer]) |> miles_to_km(2),
      locked: get_in_struct(vehicle, [:vehicle_state, :locked]),
      sentry_mode: get_in_struct(vehicle, [:vehicle_state, :sentry_mode]),
      windows_open: window_open(vehicle),
      doors_open: doors_open(vehicle),
      trunk_open: trunk_open(vehicle),
      frunk_open: frunk_open(vehicle),
      is_user_present: get_in_struct(vehicle, [:vehicle_state, :is_user_present]),
      version: version(vehicle),
      update_available: update_available(vehicle),
      update_version: update_version(vehicle),
      tpms_pressure_fl: get_in_struct(vehicle, [:vehicle_state, :tpms_pressure_fl]),
      tpms_pressure_fr: get_in_struct(vehicle, [:vehicle_state, :tpms_pressure_fr]),
      tpms_pressure_rl: get_in_struct(vehicle, [:vehicle_state, :tpms_pressure_rl]),
      tpms_pressure_rr: get_in_struct(vehicle, [:vehicle_state, :tpms_pressure_rr])
    }
  end

  defp charge(vehicle, key), do: get_in_struct(vehicle, [:charge_state, key])

  defp speed(%Vehicle{drive_state: %Drive{speed: s}}) when not is_nil(s), do: mph_to_kmh(s)
  defp speed(_vehicle), do: nil

  defp plugged_in(%Vehicle{charge_state: nil}), do: nil
  defp plugged_in(%Vehicle{charge_state: %Charge{charge_port_door_open: :unknown}}), do: :unknown

  defp plugged_in(%Vehicle{charge_state: %Charge{} = c}) do
    c.charging_state != "Disconnected"
  end

  defp plugged_in(_vehicle), do: nil

  defp window_open(%Vehicle{vehicle_state: vehicle_state}) do
    case vehicle_state do
      %VehicleState{fd_window: fd, fp_window: fp, rd_window: rd, rp_window: rp}
      when is_number(fd) and is_number(fp) and is_number(rd) and is_number(rp) ->
        fd > 0 or fp > 0 or rd > 0 or rp > 0

      _ ->
        nil
    end
  end

  defp doors_open(%Vehicle{vehicle_state: vehicle_state}) do
    case vehicle_state do
      %VehicleState{df: df, pf: pf, dr: dr, pr: pr}
      when is_number(df) and is_number(pf) and is_number(dr) and is_number(pr) ->
        df > 0 or pf > 0 or dr > 0 or pr > 0

      _ ->
        nil
    end
  end

  defp trunk_open(%Vehicle{vehicle_state: %VehicleState{rt: rt}}) when is_number(rt), do: rt > 0
  defp trunk_open(_vehicle), do: nil

  defp frunk_open(%Vehicle{vehicle_state: %VehicleState{ft: ft}}) when is_number(ft), do: ft > 0
  defp frunk_open(_vehicle), do: nil

  defp version(vehicle) do
    with %Vehicle{vehicle_state: %VehicleState{car_version: v}} when is_binary(v) <- vehicle,
         [version | _] <- String.split(v, " ") do
      version
    else
      _ -> nil
    end
  end

  defp update_available(vehicle) do
    case get_in_struct(vehicle, [:vehicle_state, :software_update, :status]) do
      status when status in ["available", "downloading", "downloading_wifi_wait"] -> true
      status when is_binary(status) -> false
      nil -> nil
    end
  end

  defp update_version(vehicle) do
    case get_in_struct(vehicle, [:vehicle_state, :software_update, :version]) do
      version when is_binary(version) -> List.first(String.split(version, " "))
      nil -> nil
    end
  end

  defp to_datetime(val) when val in [nil, :unknown], do: val
  defp to_datetime(ts), do: DateTime.from_unix!(ts)

  defp get_in_struct(struct, keys) do
    Enum.reduce(keys, struct, fn key, acc -> if acc, do: Map.get(acc, key) end)
  end
end
