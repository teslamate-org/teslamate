defmodule TeslaMate.IdentificationTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Vehicles.Identification

  alias TeslaApi.Vehicle.State.VehicleConfig, as: Config
  alias TeslaApi.Vehicle

  import ExUnit.CaptureLog

  defp vehicle_fixture(config) do
    %Vehicle{vehicle_config: struct(Config, config)}
  end

  test "detects common Model S, 3 and X" do
    assert %{model: "S", trim_badging: "90D", efficiency: 0.188} ==
             vehicle_fixture(%{car_type: "models2", trim_badging: "90d"})
             |> Identification.properties()

    assert %{model: "3", trim_badging: nil, efficiency: 0.153} ==
             vehicle_fixture(%{car_type: "model3", trim_badging: nil})
             |> Identification.properties()

    assert %{model: "X", trim_badging: "P100D", efficiency: 0.226} ==
             vehicle_fixture(%{car_type: "modelx", trim_badging: "p100d"})
             |> Identification.properties()
  end

  test "fails to detect new models" do
    test_cases = [
      {"modely", nil, nil},
      {"models3", "p200d", "S"},
      {"modelx", "p200d", "X"},
      {"model3", "LR", "3"}
    ]

    for {car_type, trim_badging, model} <- test_cases do
      assert capture_log(fn ->
               assert %{model: model, trim_badging: upcase(trim_badging), efficiency: nil} ==
                        vehicle_fixture(%{car_type: car_type, trim_badging: trim_badging})
                        |> Identification.properties()
             end) =~ """
             [warn] Vehicle could not be identified!

             %TeslaApi.Vehicle.State.VehicleConfig{
               can_accept_navigation_requests: nil,
               can_actuate_trunks: nil,
               car_special_type: nil,
               car_type: #{inspect(car_type)},
               charge_port_type: nil,
               eu_vehicle: nil,
               exterior_color: nil,
               has_air_suspension: nil,
               has_ludicrous_mode: nil,
               key_version: nil,
               motorized_charge_port: nil,
               perf_config: nil,
               plg: nil,
               rear_seat_heaters: nil,
               rear_seat_type: nil,
               rhd: nil,
               roof_color: nil,
               seat_type: nil,
               spoiler_type: nil,
               sun_roof_installed: nil,
               third_row_seats: nil,
               timestamp: nil,
               trim_badging: #{inspect(trim_badging)},
               wheel_type: nil
             }
             """
    end
  end

  defp upcase(nil), do: nil
  defp upcase(str), do: String.upcase(str)
end
