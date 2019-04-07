defmodule TeslaMate.Vehicles.Vehicle.Identification do
  def properties(%TeslaApi.Vehicle{} = vehicle) do
    performance = vehicle.option_codes |> Enum.find(false, &is_performance/1)
    battery = vehicle.option_codes |> Enum.find_value(&which_battery/1)
    model = vehicle.option_codes |> Enum.find_value(&which_model/1)
    awd = vehicle.option_codes |> Enum.member?("DV4W")

    {name, efficiency} = get_efficiency(model, battery, performance, awd)

    %{
      name: name,
      model: model,
      battery: battery,
      awd: awd,
      performance: performance,
      efficiency: efficiency
    }
  end

  defp which_model("MDLS"), do: "MS"
  defp which_model("MS01"), do: "MS"
  defp which_model("MS02"), do: "MS"
  defp which_model("MS03"), do: "MS"
  defp which_model("MDLX"), do: "MX"
  defp which_model("MDL3"), do: "M3"
  defp which_model(______), do: false

  defp is_performance("PX01"), do: true
  defp is_performance("P85D"), do: true
  defp is_performance("PX6D"), do: true
  defp is_performance("X024"), do: true
  defp is_performance("PBT8"), do: true
  defp is_performance(______), do: nil

  defp which_battery("BT" <> _ = battery), do: battery
  defp which_battery(_), do: nil

  defp get_efficiency("MS", "BTX5", _, true), do: {"S 75D", 0.186}
  defp get_efficiency("MS", "BTX5", _, false), do: {"S 75", 0.185}
  defp get_efficiency("MS", "BTX4", true, _), do: {"S P90D", 0.200}
  defp get_efficiency("MS", "BTX4", false, _), do: {"S 90D", 0.189}
  defp get_efficiency("MS", "BTX6", true, _), do: {"S P100D", 0.200}
  defp get_efficiency("MS", "BTX6", false, _), do: {"S 100D", 0.189}
  defp get_efficiency("MS", "BTX8", _, true), do: {"S 75D (85kWh)", 0.186}
  defp get_efficiency("MS", "BTX8", _, false), do: {"S 75 (85kWh)", 0.185}
  defp get_efficiency("MS", "BT85", _, _), do: {"S 85 ?", 0.200}
  defp get_efficiency("MS", "BT70", _, _), do: {"S 70 ?", 0.200}
  defp get_efficiency("MS", "BT60", _, _), do: {"S 60 ?", 0.200}
  defp get_efficiency("MS", _, _, _), do: {"S ???", 0.200}

  defp get_efficiency("MX", "BTX5", _, _), do: {"X 75D", 0.208}
  defp get_efficiency("MX", "BTX4", true, _), do: {"X 90D", 0.208}
  defp get_efficiency("MX", "BTX4", false, _), do: {"X P90D", 0.217}
  defp get_efficiency("MX", "BTX6", true, _), do: {"X P100D", 0.226}
  defp get_efficiency("MX", "BTX6", false, _), do: {"X 100D", 0.208}
  defp get_efficiency("MX", _, _, _), do: {"X ???", 0.208}

  defp get_efficiency("M3", "BT37", _, _), do: {"M3 LR", 0.153}
  defp get_efficiency("M3", _, _, _), do: {"M3 ???", 0.153}

  defp get_efficiency(_, _, _, _), do: {"???", nil}
end
