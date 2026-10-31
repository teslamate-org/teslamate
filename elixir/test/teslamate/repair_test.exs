defmodule TeslaMate.RepairTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.{Log, Repair}
  alias TeslaMate.Log.{ChargingProcess, Drive}

  setup do
    # Nominatim has had a break since the requests of earlier tests
    :ok = GeocoderMock.advance(:timer.minutes(1))
    :ok = GeocoderMock.report_pauses()
  end

  test "fills in the missing addresses, spacing the requests to Nominatim" do
    {:ok, car} = Log.create_car(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42, vin: "xxxxx"})

    {:ok, drive} = Log.start_drive(car)

    for {date, lat, lng, km} <- [
          {"2019-04-06 10:19:02", 52.514521, 13.350144, 284.8},
          {"2019-04-06 10:20:08", 52.394246, 13.542552, 285.9}
        ] do
      {:ok, _} =
        Log.insert_position(drive, %{
          date: date,
          latitude: lat,
          longitude: lng,
          odometer: km,
          ideal_battery_range_km: 300
        })
    end

    {:ok, %Drive{start_address_id: nil, end_address_id: nil}} = Log.close_drive(drive)

    {:ok, %ChargingProcess{address_id: nil} = cproc} =
      Log.start_charging_process(car, %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0})

    # Runs the repair in the test process, which is told about each pause
    assert {:noreply, _state} = Repair.handle_cast(:repair, %Repair.State{limit: 10})

    # three lookups: the first right away, the others after the interval
    assert_received {:pause, 1500, checked_out?: false}
    assert_received {:pause, 1500, checked_out?: false}
    refute_received {:pause, _, _}

    assert %Drive{start_address_id: start_id, end_address_id: end_id} =
             Repo.get!(Drive, drive.id)

    assert %ChargingProcess{address_id: address_id} = Repo.get!(ChargingProcess, cproc.id)
    assert Enum.all?([start_id, end_id, address_id], &is_integer/1)
  end
end
