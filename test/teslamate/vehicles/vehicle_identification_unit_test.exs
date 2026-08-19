defmodule TeslaMate.Vehicles.Vehicle.IdentificationUnitTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Vehicles.Vehicle

  describe "format_model/1" do
    test "prefixes Model S/3/X/Y but not Cybertruck" do
      for model <- ~w(S 3 X Y) do
        assert "Model #{model}" == Vehicle.format_model(model)
      end

      assert "Cybertruck" == Vehicle.format_model("Cybertruck")
    end
  end

  describe "identify/1" do
    for {year, year_code} <- [{2019, "K"}, {2020, "L"}, {2021, "M"}] do
      test "identifies a #{year} base Model 3 as SR+" do
        assert "SR+" == identify_model_3_base(unquote(year_code))
      end
    end

    for {year, year_code} <- [{2022, "N"}, {2023, "P"}, {2024, "R"}, {2039, "9"}] do
      test "identifies a #{year} base Model 3 as RWD" do
        assert "RWD" == identify_model_3_base(unquote(year_code))
      end
    end

    test "falls back to SR+ for a malformed VIN" do
      assert "SR+" == identify_model_3_base("invalid")
    end

    test "falls back to SR+ for an invalid model-year character" do
      assert "SR+" == identify_model_3_base("Z")
    end

    test "falls back to SR+ when the VIN is missing" do
      assert "SR+" == identify_model_3_base(nil)
    end

    test "identifies Cybertruck car type variants" do
      for car_type <- ~w(cybertruck cybertruck2) do
        vehicle = %TeslaApi.Vehicle{
          vehicle_config: %TeslaApi.Vehicle.State.VehicleConfig{
            car_type: car_type,
            trim_badging: "foundation"
          }
        }

        assert {:ok,
                %{
                  model: "Cybertruck",
                  trim_badging: "FOUNDATION",
                  marketing_name: nil
                }} = Vehicle.identify(vehicle)
      end
    end
  end

  defp identify_model_3_base(year_code) when byte_size(year_code) == 1 do
    identify_model_3_base("5YJ3E1EA1#{year_code}F000000")
  end

  defp identify_model_3_base(vin) do
    vehicle = %TeslaApi.Vehicle{
      vin: vin,
      vehicle_config: %TeslaApi.Vehicle.State.VehicleConfig{
        car_type: "model3",
        trim_badging: "50"
      }
    }

    assert {:ok, %{marketing_name: marketing_name}} = Vehicle.identify(vehicle)
    marketing_name
  end
end
