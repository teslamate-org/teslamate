defmodule TeslaMate.Vehicles.Vehicle.IdentificationTest do
  use TeslaMate.VehicleCase, async: false
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Log.Car
  alias TeslaMate.Log

  test "identifies the vehicle" do
    events = [
      {:ok,
       online_event(
         display_name: "FooBar",
         vehicle_config: %{car_type: "models", trim_badging: "p100d"}
       )}
    ]

    :ok = start_vehicles(events)

    TestHelper.eventually(fn ->
      assert %Car{name: "FooBar", model: "S", trim_badging: "P100D"} = Log.get_car_by(vid: 90211)
    end)
  end

  test "changes the car name" do
    events = [
      {:ok, online_event(display_name: "FooBar")},
      {:ok, online_event(display_name: "FooBar")},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, %TeslaApi.Vehicle{state: "offline"}},
      {:ok, online_event(display_name: "Bar")},
      {:ok, online_event(display_name: "Bar")}
    ]

    :ok = start_vehicles(events)

    TestHelper.eventually(fn -> assert %Car{name: "FooBar"} = Log.get_car_by(vid: 90211) end,
      delay: 10,
      attempts: 50
    )

    TestHelper.eventually(fn -> assert %Car{name: "Bar"} = Log.get_car_by(vid: 90211) end,
      delay: 50,
      attempts: 20
    )
  end

  def start_vehicles(events \\ []) do
    {:ok, _pid} = start_supervised({ApiMock, name: :api_vehicle, events: events, pid: self()})

    {:ok, _pid} =
      start_supervised(
        {TeslaMate.Vehicles,
         vehicle: VehicleMock,
         vehicles: [
           %TeslaApi.Vehicle{
             display_name: "Foo",
             id: 11243,
             vehicle_id: 90211,
             vin: "absadkalfs"
           }
         ]}
      )

    :ok
  end
end
