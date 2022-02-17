defmodule TeslaMate.Vehicles.Vehicle.ChargingSyncTest do
  use TeslaMate.VehicleCase, async: false

  import ExUnit.CaptureLog

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log

  @log_opts format: "[$level] $message\n",
            colors: [enabled: false]

  @tag :capture_log
  test "handles invalid charge data", %{test: name} do
    %{eid: eid} = car = car_fixture()
    now_ts = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    events = [
      {:ok, online_event()},
      {:ok, online_event(drive_state: %{timestamp: now_ts, latitude: 0.0, longitude: 0.0})},
      {:ok, charging_event(now_ts, "Charging", 0.1, range: nil)},
      {:ok, charging_event(now_ts, "Charging", 0.1, range: nil)},
      {:ok, charging_event(now_ts, "Charging", 0.2, range: 10)}
    ]

    assert capture_log(@log_opts, fn ->
             :ok = start_vehicle(name, events, car: car, log: false)

             true =
               name
               |> Process.whereis()
               |> Process.link()

             assert_receive {ApiMock, {:stream, ^eid, _}}
             assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :online}}}
             assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
             assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :charging}}}
             assert_receive {:"$websockex_cast", :disconnect}

             refute_receive _
           end) =~
             ~r"""
             \[warn.*\] Invalid charge data: %{ideal_battery_range_km: \[\"can't be blank\"\]}
             \[warn.*\] Invalid charge data: %{ideal_battery_range_km: \[\"can't be blank\"\]}
             """
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{
        efficiency: 0.153,
        eid: 13442,
        model: "S",
        vid: 13442,
        name: "foo",
        trim_badging: "P100D",
        vin: "13412345F"
      })
      |> Log.create_car()

    car
  end
end
