defmodule TeslaMate.Vehicles.Identification do
  def properties(%TeslaApi.Vehicle{} = vehicle) do
    performance = vehicle.option_codes |> Enum.find(false, &is_performance/1)
    battery = vehicle.option_codes |> Enum.find_value(&which_battery/1)
    model = vehicle.option_codes |> Enum.find_value(&which_model/1)
    awd = vehicle.option_codes |> Enum.member?("DV4W")

    {version, efficiency} = get_efficiency(model, battery, performance, awd)

    %{
      version: version,
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
  defp which_model("MS04"), do: "MS"
  defp which_model("MDLX"), do: "MX"
  defp which_model("MDL3"), do: "M3"
  defp which_model(______), do: false

  defp is_performance("P85D"), do: true
  defp is_performance("PBT8"), do: true
  defp is_performance("PF01"), do: true
  defp is_performance("PX01"), do: true
  defp is_performance("PX6D"), do: true
  defp is_performance("SPT31"), do: true
  defp is_performance("MT304"), do: true
  defp is_performance("X024"), do: true
  defp is_performance(______), do: false

  defp which_battery("BT" <> _ = battery), do: battery
  defp which_battery(_), do: nil

  defp get_efficiency("MS", "BTX5", _perf, true), do: {"S 75D", 0.186}
  defp get_efficiency("MS", "BTX5", _perf, false), do: {"S 75", 0.185}
  defp get_efficiency("MS", "BTX4", true, _awd), do: {"S P90D", 0.200}
  defp get_efficiency("MS", "BTX4", false, _awd), do: {"S 90D", 0.189}
  defp get_efficiency("MS", "BTX6", true, _awd), do: {"S P100D", 0.200}
  defp get_efficiency("MS", "BTX6", false, _awd), do: {"S 100D", 0.189}
  defp get_efficiency("MS", "BTX8", _perf, true), do: {"S 75D (85kWh)", 0.186}
  defp get_efficiency("MS", "BTX8", _perf, false), do: {"S 75 (85kWh)", 0.185}
  defp get_efficiency("MS", "BT85", true, true), do: {"S P85D", 0.201}
  defp get_efficiency("MS", "BT85", false, true), do: {"S 85D", 0.186}
  defp get_efficiency("MS", "BT85", true, false), do: {"S P85", 0.210}
  defp get_efficiency("MS", "BT85", false, false), do: {"S 85", 0.201}
  defp get_efficiency("MS", "BT70", _perf, _awd), do: {"S 70 ?", 0.200}
  defp get_efficiency("MS", "BT60", _perf, _awd), do: {"S 60 ?", 0.200}
  defp get_efficiency("MS", ______, _perf, _awd), do: {"S ???", 0.200}

  defp get_efficiency("MX", "BTX5", _perf, _awd), do: {"X 75D", 0.208}
  defp get_efficiency("MX", "BTX4", false, _awd), do: {"X 90D", 0.208}
  defp get_efficiency("MX", "BTX4", true, _awd), do: {"X P90D", 0.217}
  defp get_efficiency("MX", "BTX6", false, _awd), do: {"X 100D", 0.208}
  defp get_efficiency("MX", "BTX6", true, _awd), do: {"X P100D", 0.226}
  defp get_efficiency("MX", ______, _perf, _awd), do: {"X ???", 0.208}

  defp get_efficiency("M3", "BT37", false, _awd), do: {"3", 0.153}
  defp get_efficiency("M3", "BT37", true, _awd), do: {"3P", 0.153}
  defp get_efficiency("M3", ______, _perf, _awd), do: {"3 ???", 0.153}

  defp get_efficiency(_, _, _, _), do: {"???", nil}
end
