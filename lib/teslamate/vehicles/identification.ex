defmodule TeslaMate.Vehicles.Identification do
  alias TeslaApi.Vehicle.State.VehicleConfig, as: Config
  alias TeslaApi.Vehicle

  require Logger

  def properties(%Vehicle{vehicle_config: %Config{car_type: type, trim_badging: badging} = conf}) do
    model = type |> String.downcase() |> get_model()
    trim_badging = badging |> upcase()

    efficiency =
      with :unkown <- get_efficiency(model, trim_badging) do
        Logger.warn("Vehicle could not be identified!\n\n#{inspect(conf, pretty: true)}")
        nil
      end

    %{model: model, efficiency: efficiency, trim_badging: trim_badging}
  end

  defp upcase(nil), do: nil
  defp upcase(str) when is_binary(str), do: String.upcase(str)

  defp get_model("models" <> _), do: "S"
  defp get_model("modelx" <> _), do: "X"
  defp get_model("model3" <> _), do: "3"
  defp get_model(_____________), do: nil

  # Source of efficiency values:
  # https://github.com/bassmaster187/TeslaLogger/blob/master/TeslaLogger/WebHelper.cs#L414

  defp get_efficiency("S", "40"), do: nil
  defp get_efficiency("S", "60"), do: 0.200
  defp get_efficiency("S", "60D"), do: nil
  defp get_efficiency("S", "70"), do: 0.200
  defp get_efficiency("S", "70D"), do: nil
  defp get_efficiency("S", "75"), do: 0.185
  defp get_efficiency("S", "75D"), do: 0.186
  defp get_efficiency("S", "85"), do: 0.185
  defp get_efficiency("S", "P85"), do: 0.210
  defp get_efficiency("S", "P85+"), do: nil
  defp get_efficiency("S", "85D"), do: 0.186
  defp get_efficiency("S", "P85D"), do: 0.201
  defp get_efficiency("S", "90"), do: nil
  defp get_efficiency("S", "90D"), do: 0.189
  defp get_efficiency("S", "P90D"), do: 0.200
  defp get_efficiency("S", "100D"), do: 0.189
  defp get_efficiency("S", "P100D"), do: 0.200
  defp get_efficiency("S", _______), do: :unkown

  defp get_efficiency("X", "60D"), do: nil
  defp get_efficiency("X", "75D"), do: 0.208
  defp get_efficiency("X", "90D"), do: 0.208
  defp get_efficiency("X", "P90D"), do: 0.217
  defp get_efficiency("X", "100D"), do: 0.208
  defp get_efficiency("X", "P100D"), do: 0.226
  defp get_efficiency("X", _______), do: :unkown

  defp get_efficiency("3", nil), do: 0.153
  defp get_efficiency("3", ___), do: :unkown

  defp get_efficiency(____, ___), do: :unkown
end
