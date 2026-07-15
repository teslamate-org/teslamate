defmodule TeslaMate.Import.LineParserTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Vehicle.State.Charge
  alias TeslaMate.Import.LineParser

  test "rounds fractional battery levels from TeslaFi exports" do
    assert %TeslaApi.Vehicle{
             charge_state: %Charge{battery_level: 28, usable_battery_level: 29}
           } =
             LineParser.parse(
               %{"battery_level" => "28.01", "usable_battery_level" => "28.5"},
               "Etc/UTC"
             )

    assert %TeslaApi.Vehicle{
             charge_state: %Charge{battery_level: 29, usable_battery_level: 30}
           } =
             LineParser.parse(
               %{"battery_level" => "29", "usable_battery_level" => "30"},
               "Etc/UTC"
             )
  end
end
