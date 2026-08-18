defmodule TeslaMate.ChargingCostSyncTest do
  use ExUnit.Case, async: true

  alias TeslaApi.ChargingHistory.{Result, Session}
  alias TeslaMate.ChargingCostSync

  defmodule ApiMock do
    def get_charging_history(agent, vin, opts) do
      Agent.get_and_update(agent, fn state ->
        send(state.test_pid, {:api_call, vin, opts})
        {Map.fetch!(state.responses, vin), state}
      end)
    end
  end

  defmodule LogMock do
    def list_cars(agent), do: Agent.get(agent, & &1.cars)

    def sync_charging_cost(agent, car, session) do
      Agent.get_and_update(agent, fn state ->
        send(state.test_pid, {:log_call, car.vin, session.id})
        {{:ok, session.id}, state}
      end)
    end
  end

  test "backfills every vehicle, isolates failures and then requests only the first page" do
    session = %Session{id: "session", start_date: DateTime.utc_now(), cost: Decimal.new(1)}
    test_pid = self()

    {:ok, agent} =
      start_supervised(
        {Agent,
         fn ->
           %{
             test_pid: test_pid,
             cars: [%{id: 1, vin: "VIN-1"}, %{id: 2, vin: "VIN-2"}],
             responses: %{
               "VIN-1" => {:error, :unavailable},
               "VIN-2" => {:ok, %Result{sessions: [session], total_results: 1}}
             }
           }
         end}
      )

    name = Module.concat(__MODULE__, "Worker#{System.unique_integer([:positive])}")

    start_supervised!(
      {ChargingCostSync,
       name: name, api: {ApiMock, agent}, log: {LogMock, agent}, interval: :timer.hours(1)}
    )

    assert_receive {:api_call, "VIN-1", [page_limit: :all]}
    assert_receive {:api_call, "VIN-2", [page_limit: :all]}
    assert_receive {:log_call, "VIN-2", "session"}

    Agent.update(agent, &put_in(&1.responses["VIN-1"], {:ok, %Result{sessions: []}}))
    ChargingCostSync.trigger_sync(name)

    assert_receive {:api_call, "VIN-1", [page_limit: :all]}
    assert_receive {:api_call, "VIN-2", [page_limit: 1]}
  end
end
