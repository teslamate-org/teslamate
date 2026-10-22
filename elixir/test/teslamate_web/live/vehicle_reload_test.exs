defmodule TeslaMateWeb.VehicleReloadTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Log.Car
  alias TeslaMateWeb.VehicleReload

  test "names newly logged cars by their title, unnamed ones by their VIN" do
    cars = [
      %Car{name: "named", vin: "5YJ3E1EB1KF000002"},
      %Car{name: nil, vin: "5YJ3E1EA1KF000001"}
    ]

    assert VehicleReload.hint({:ok, cars}) ==
             "Started logging for: named, VIN 5YJ3E1EA1KF000001"
  end
end
