defmodule TeslaMate.MutexTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Mutex

  setup context do
    name = :"#{inspect(__MODULE__)}.#{context.test}"
    mutex = start_supervised!({Mutex, name: name})
    {:ok, mutex: mutex}
  end

  # Runs `name` under the mutex in a task that reports entering and leaves
  # on :leave.
  defp holder(mutex, name) do
    test = self()

    Task.async(fn ->
      Mutex.run(mutex, fn ->
        send(test, {:entered, name})
        receive do: (:leave -> name)
      end)
    end)
  end

  # Starts `name` behind the current holder and returns once it waits.
  defp waiter(mutex, name) do
    :erlang.trace(mutex, true, [:receive])
    task = holder(mutex, name)
    %Task{pid: pid} = task
    assert_receive {:trace, ^mutex, :receive, {:"$gen_call", {^pid, _}, :acquire}}
    :erlang.trace(mutex, false, [:receive])

    # the mutex has handled the request and queued it
    assert %{waiting: waiting} = :sys.get_state(mutex)
    assert Enum.any?(:queue.to_list(waiting), &match?({{^pid, _tag}, _ref}, &1))

    task
  end

  test "runs the function in the calling process and returns its result", %{mutex: mutex} do
    test = self()
    assert ^test = Mutex.run(mutex, fn -> self() end)
  end

  test "lets a second caller in only after the first one left", %{mutex: mutex} do
    first = holder(mutex, :first)
    assert_receive {:entered, :first}

    second = waiter(mutex, :second)
    refute_received {:entered, :second}

    send(first.pid, :leave)
    assert :first = Task.await(first)

    assert_receive {:entered, :second}
    send(second.pid, :leave)
    assert :second = Task.await(second)
  end

  test "lets callers in in the order they asked", %{mutex: mutex} do
    first = holder(mutex, :first)
    assert_receive {:entered, :first}

    second = waiter(mutex, :second)
    third = waiter(mutex, :third)

    send(first.pid, :leave)
    assert_receive {:entered, :second}
    refute_received {:entered, :third}

    send(second.pid, :leave)
    assert_receive {:entered, :third}
    send(third.pid, :leave)

    assert [:first, :second, :third] = Task.await_many([first, second, third])
  end

  test "releases the lock when the function raises", %{mutex: mutex} do
    assert_raise RuntimeError, "boom", fn -> Mutex.run(mutex, fn -> raise "boom" end) end
    assert :ok = Mutex.run(mutex, fn -> :ok end)
  end

  test "releases the lock when the holder dies", %{mutex: mutex} do
    Process.flag(:trap_exit, true)

    first = holder(mutex, :first)
    assert_receive {:entered, :first}
    second = waiter(mutex, :second)

    Process.exit(first.pid, :kill)
    assert_receive {:entered, :second}

    send(second.pid, :leave)
    assert :second = Task.await(second)
  end

  test "drops a caller that dies while waiting", %{mutex: mutex} do
    Process.flag(:trap_exit, true)

    first = holder(mutex, :first)
    assert_receive {:entered, :first}
    second = waiter(mutex, :second)
    third = waiter(mutex, :third)

    Process.exit(second.pid, :kill)
    assert_receive {:EXIT, _, :killed}

    send(first.pid, :leave)
    assert_receive {:entered, :third}
    refute_received {:entered, :second}

    send(third.pid, :leave)
    assert :third = Task.await(third)
  end
end
