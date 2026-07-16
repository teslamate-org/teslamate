defmodule TeslaApi.StreamTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Stream

  test "emits socket liveness separately from the existing data receiver" do
    test_pid = self()
    receiver = fn event -> send(test_pid, {:data, event}) end
    liveness_receiver = fn event -> send(test_pid, {:liveness, event}) end

    state = %Stream.State{
      receiver: receiver,
      liveness_receiver: liveness_receiver,
      vehicle_id: 42
    }

    assert {:ok, ^state} = Stream.handle_connect(nil, state)
    assert_receive {:liveness, :connected}
    assert_receive :subscribe
    refute_receive {:data, _event}

    disconnect = %{reason: {:local, :normal}, attempt_number: 1}
    assert {:reconnect, ^state} = Stream.handle_disconnect(disconnect, state)
    assert_receive {:liveness, :reconnecting}
    refute_receive {:data, _event}
  end

  test "reports a requested shutdown as disconnected" do
    test_pid = self()
    receiver = fn event -> send(test_pid, {:data, event}) end
    liveness_receiver = fn event -> send(test_pid, {:liveness, event}) end

    state = %Stream.State{
      receiver: receiver,
      liveness_receiver: liveness_receiver,
      vehicle_id: 42
    }

    assert {:reply, {:text, _frame}, ^state} = Stream.handle_cast(:disconnect, state)
    assert_receive {:liveness, :disconnected}
    assert_receive :exit
    refute_receive {:data, _event}
  end

  test "classifies a timeout close as reconnecting" do
    test_pid = self()
    liveness_receiver = fn event -> send(test_pid, {:liveness, event}) end
    state = %Stream.State{liveness_receiver: liveness_receiver, vehicle_id: 42}

    assert {:close, %Stream.State{} = timed_out} = Stream.handle_info(:timeout, state)
    assert timed_out.timeouts == 1

    disconnect = %{reason: {:local, :normal}, attempt_number: 1}
    assert {:reconnect, ^timed_out} = Stream.handle_disconnect(disconnect, timed_out)
    assert_receive {:liveness, :reconnecting}
  end
end
