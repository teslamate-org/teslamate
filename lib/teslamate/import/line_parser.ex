defmodule TeslaMate.Import.LineParser do
  use Timex

  require Logger

  alias TeslaApi.Vehicle.State.{Charge, Climate, Drive, VehicleConfig, VehicleState}
  alias TeslaApi.Vehicle

  @default_vehicle %{
    "display_name" => "",
    "charge_state" => %{},
    "climate_state" => %{},
    "drive_state" => %{},
    "vehicle_config" => %{},
    "vehicle_state" => %{}
  }

  def parse(line, tz) when is_map(line) do
    line
    |> Enum.reduce(@default_vehicle, &into_vehicle(&1, &2, tz))
    |> Vehicle.result()
  end

  @charge_state %Charge{} |> Map.keys() |> Enum.map(&to_string/1)
  @climate_state %Climate{} |> Map.keys() |> Enum.map(&to_string/1)
  @drive_state %Drive{} |> Map.keys() |> Enum.map(&to_string/1)
  @vehicle %Vehicle{} |> Map.keys() |> Enum.map(&to_string/1)
  @vehicle_config %VehicleConfig{} |> Map.keys() |> Enum.map(&to_string/1)
  @vehicle_state %VehicleState{} |> Map.keys() |> Enum.map(&to_string/1)

  defp map_value(_, ""), do: nil
  defp map_value(_, "None"), do: nil
  defp map_value(_, "none"), do: nil

  defp map_value(_, "TRUE"), do: true
  defp map_value(_, "True"), do: true
  defp map_value(_, "true"), do: true
  defp map_value(_, "FALSE"), do: false
  defp map_value(_, "False"), do: false
  defp map_value(_, "false"), do: false

  defp map_value("display_name", name), do: name
  defp map_value("state", "waking"), do: "online"
  defp map_value("state", "shutdown"), do: "online"

  defp map_value("scheduled_charging_start_time", _val), do: nil

  @boolean ~w(battery_heater_on is_climate_on is_front_defroster_on is_rear_defroster_on
              fast_charger_present not_enough_power_to_heat)

  defp map_value(key, val) when key in @boolean do
    with v when v not in [nil, false, true] <- map_value(nil, val) do
      nil
    end
  end

  defp map_value(_key, val) do
    case Integer.parse(val) do
      {i, ""} -> i
      {_, _} -> to_float(val)
      :error -> val
    end
  end

  defp to_float(val) do
    case Float.parse(val) do
      {f, ""} -> f
      {_, _} -> val
      :error -> val
    end
  end

  defp into_vehicle({key, val}, acc, tz) do
    case {key, val} do
      {"id", _val} ->
        Map.put(acc, "id", :rand.uniform(65536))

      {"Date", val} ->
        {:ok, datetime} =
          with {:error, _reason} <- Timex.parse(val, "{YYYY}-{M}-{D} {h24}:{m}:{s}"),
               {:error, _reason} <- Timex.parse(val, "{M}/{D}/{YYYY} {h12}:{m}:{s} {AM}"),
               {:error, _reason} <- Timex.parse(val, "{M}/{D}/{YYYY} {h24}:{m}") do
            {:error, {:invalid_date_format, val}}
          end

        ts =
          case DateTime.from_naive(datetime, tz) do
            {:ok, datetime} ->
              DateTime.to_unix(datetime, :millisecond)

            {kind, _first_dt, _second_dt} when kind in [:ambiguous, :gap] ->
              # To keep things simple, return nil to ignore these ambiguous responses
              nil

            {:error, reason} ->
              Logger.warning(
                "Could not convert date #{inspect(datetime)} w/ time zone #{inspect(tz)}: #{
                  inspect(reason)
                }"
              )

              nil
          end

        ["vehicle_config", "vehicle_state", "drive_state", "climate_state", "charge_state"]
        |> Enum.reduce(acc, fn key, acc -> put_in(acc, [key, "timestamp"], ts) end)

      {key, val} when key in @charge_state ->
        put_in(acc, ["charge_state", key], map_value(key, val))

      {key, val} when key in @climate_state ->
        put_in(acc, ["climate_state", key], map_value(key, val))

      {key, val} when key in @drive_state ->
        put_in(acc, ["drive_state", key], map_value(key, val))

      {key, val} when key in @vehicle_config ->
        put_in(acc, ["vehicle_config", key], map_value(key, val))

      {key, val} when key in @vehicle_state ->
        put_in(acc, ["vehicle_state", key], map_value(key, val))

      {key, val} when key in @vehicle ->
        Map.put(acc, key, map_value(key, val))

      {key, val} ->
        Logger.debug("unhandled: #{inspect({key, val})}")
        acc
    end
  end
end
