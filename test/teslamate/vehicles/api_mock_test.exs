defmodule TeslaMate.Vehicles.ApiMockTest do
  use ExUnit.Case, async: true

  test "reuses an online snapshot for a lightweight and full-data fetch" do
    first = {:ok, %TeslaApi.Vehicle{state: "online", display_name: "first"}}
    second = {:ok, %TeslaApi.Vehicle{state: "online", display_name: "second"}}
    name = start_api_mock([{:snapshot, first}, second])

    assert ApiMock.get_vehicle(name, 1) == first
    assert ApiMock.get_vehicle_with_state(name, 1) == first
    assert ApiMock.get_vehicle(name, 1) == second
  end

  test "evaluates a reused snapshot only once" do
    test_pid = self()

    event = fn ->
      send(test_pid, :event_evaluated)
      {:ok, %TeslaApi.Vehicle{state: "online"}}
    end

    name = start_api_mock([{:snapshot, event}])

    assert {:ok, %TeslaApi.Vehicle{state: "online"}} = ApiMock.get_vehicle(name, 1)
    assert {:ok, %TeslaApi.Vehicle{state: "online"}} = ApiMock.get_vehicle_with_state(name, 1)
    assert_receive :event_evaluated
    refute_receive :event_evaluated
  end

  test "does not reuse a snapshot for a different vehicle" do
    test_pid = self()

    event = fn ->
      send(test_pid, :event_evaluated)
      {:ok, %TeslaApi.Vehicle{state: "online"}}
    end

    name = start_api_mock([{:snapshot, event}])

    assert {:ok, %TeslaApi.Vehicle{state: "online"}} = ApiMock.get_vehicle(name, 1)
    assert_receive :event_evaluated

    assert {:ok, %TeslaApi.Vehicle{state: "online"}} = ApiMock.get_vehicle_with_state(name, 2)
    assert_receive :event_evaluated
  end

  test "reuses a snapshot nested inside an endpoint wrapper" do
    first = {:ok, %TeslaApi.Vehicle{state: "online", display_name: "first"}}
    second = {:ok, %TeslaApi.Vehicle{state: "online", display_name: "second"}}
    name = start_api_mock([{:get_vehicle, {:snapshot, first}}, second])

    assert ApiMock.get_vehicle(name, 1) == first
    assert ApiMock.get_vehicle_with_state(name, 1) == first
    assert ApiMock.get_vehicle(name, 1) == second
  end

  defp start_api_mock(events) do
    start_supervised!({ApiMock, events: events, pid: self()})
  end
end
