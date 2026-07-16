defmodule TeslaMate.Import.FakeApiTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Vehicle
  alias TeslaApi.Vehicle.State.Drive
  alias TeslaMate.Import.{FakeApi, RejectedRow}

  test "continues across reject-only chunks and reports every rejection once" do
    name = :"fake_api_#{System.unique_integer([:positive])}"

    rejections =
      Enum.map(1..1000, fn row ->
        {:reject, RejectedRow.new("TeslaFi12018.csv", row, :parse_error)}
      end)

    vehicle = %Vehicle{drive_state: %Drive{timestamp: 1}}
    stream = Stream.map(rejections ++ [{:vehicle, vehicle}], & &1)

    start_supervised!(
      {FakeApi,
       name: name,
       event_streams: [{[2018, 1], stream}],
       date_limit: ~U[2100-01-01 00:00:00Z],
       pid: self()}
    )

    caller = Task.async(fn -> FakeApi.get_vehicle(name, 1) end)

    Enum.each(1..1000, fn row ->
      assert_receive {:rejected_row, %RejectedRow{row: ^row}}, 1000
    end)

    assert {:ok, ^vehicle} = Task.await(caller, 1000)
    refute_receive {:rejected_row, _rejected_row}
  end

  test "serves callers in FIFO order while the next chunk is pending" do
    name = :"fake_api_#{System.unique_integer([:positive])}"
    parent = self()

    rejections =
      Enum.map(1..500, fn row ->
        {:reject, RejectedRow.new("TeslaFi12018.csv", row, :parse_error)}
      end)

    first_vehicle = %Vehicle{drive_state: %Drive{timestamp: 1}}
    second_vehicle = %Vehicle{drive_state: %Drive{timestamp: 2}}

    delayed_vehicles =
      Stream.resource(
        fn ->
          send(parent, {:tail_waiting, self()})

          receive do
            :release_tail -> [{:vehicle, first_vehicle}, {:vehicle, second_vehicle}]
          end
        end,
        fn
          [] -> {:halt, []}
          vehicles -> {vehicles, []}
        end,
        fn _ -> :ok end
      )

    stream = Stream.concat(rejections, delayed_vehicles)

    start_supervised!(
      {FakeApi,
       name: name,
       event_streams: [{"TeslaFi12018.csv", stream}],
       date_limit: ~U[2100-01-01 00:00:00Z],
       pid: self()}
    )

    first_caller = Task.async(fn -> FakeApi.get_vehicle(name, 1) end)

    Enum.each(1..500, fn row ->
      assert_receive {:rejected_row, %RejectedRow{row: ^row}}, 1000
    end)

    assert_receive {:tail_waiting, producer}, 1000

    second_caller = Task.async(fn -> FakeApi.get_vehicle_with_state(name, 1) end)

    TestHelper.eventually(
      fn -> assert :queue.len(:sys.get_state(name).waiters) == 2 end,
      delay: 10,
      attempts: 100
    )

    send(producer, :release_tail)

    assert {:ok, ^first_vehicle} = Task.await(first_caller, 1000)
    assert {:ok, ^second_vehicle} = Task.await(second_caller, 1000)
  end

  test "marks the final file complete only after the next fetch boundary" do
    name = :"fake_api_#{System.unique_integer([:positive])}"
    file_id = {"TeslaFi12018.csv", "fingerprint"}
    vehicle = %Vehicle{drive_state: %Drive{timestamp: 1}}

    start_supervised!(
      {FakeApi,
       name: name,
       event_streams: [{file_id, Stream.map([{:vehicle, vehicle}], & &1)}],
       date_limit: ~U[2100-01-01 00:00:00Z],
       pid: self()}
    )

    assert {:ok, ^vehicle} = FakeApi.get_vehicle(name, 1)
    refute_receive {:done, _file_id}
    refute_receive :done

    next_fetch = Task.async(fn -> FakeApi.get_vehicle(name, 1) end)

    assert_receive {:done, ^file_id}, 1000
    assert_receive :done, 1000
    Task.shutdown(next_fetch, :brutal_kill)
  end
end
