defmodule TeslaApi.StreamTest do
  use ExUnit.Case, async: true

  alias TeslaApi.Stream
  alias TeslaApi.Stream.{Data, State}

  @vid 1000

  # Columns: time,speed,odometer,soc,elevation,est_heading,est_lat,est_lng,power,shift_state,
  # range,est_range,heading. The second frame is in another column layout: it carries the
  # power in soc, the heading in est_lat, a latitude in est_lng and shift_state, and no value
  # in est_heading and power.
  @subscribed "1761486549540,,15364.2,67,45,105,52.520008,13.404954,0,,201,187,105"
  @other_layout "1761486549890,,15364.2,0,45,,105,52.520008,,52.520008,201,187,105"

  defp handle(value, %State{} = state) do
    msg = Jason.encode!(%{"msg_type" => "data:update", "tag" => "#{@vid}", "value" => value})
    {:ok, %State{}} = Stream.handle_frame({:text, msg}, state)
  end

  defp state(attrs \\ []) do
    me = self()
    struct!(%State{vehicle_id: @vid, receiver: &send(me, {:received, &1})}, attrs)
  end

  test "delivers a frame in the subscribed layout" do
    {:ok, state} = handle(@subscribed, state(timeouts: 3, disconnects: 2))

    assert_received {:received, %Data{soc: 67, power: 0, shift_state: nil, est_lat: 52.520008}}
    assert %State{last_data: %Data{soc: 67}, timeouts: 0, disconnects: 0} = state
  end

  test "drops a frame in another column layout and resets the timeout" do
    last_data = Stream.decode_frame!(@subscribed)
    timer = Process.send_after(self(), :timeout, :timer.seconds(5))
    before = state(last_data: last_data, timer: timer, timeouts: 3, disconnects: 2)

    {:ok, state} = handle(@other_layout, before)

    refute_received {:received, _}
    assert Process.read_timer(timer) == false
    assert Process.read_timer(state.timer) > :timer.seconds(5)
    assert is_reference(state.replace_timer)
    assert %State{state | timer: timer, replace_timer: nil} == before
  end

  test "drops a frame whose shift state is a latitude, also with a heading below 90" do
    {:ok, _state} = handle(String.replace(@other_layout, ",105,", ",45,"), state())

    refute_received {:received, _}
  end

  test "drops a frame with a coordinate out of range" do
    {:ok, _state} = handle("1761486549890,,15364.2,0,45,,105,13.404954,,,201,187,105", state())
    {:ok, _state} = handle("1761486549890,,15364.2,0,45,,52.520008,180.5,,,201,187,105", state())

    refute_received {:received, _}
  end

  describe "replacing the connection on garbled data" do
    test "closes the connection 10 s after a garbled frame" do
      {:ok, %State{replace_timer: ref} = state} = handle(@other_layout, state())

      assert Process.cancel_timer(ref) in (:timer.seconds(10) - 100)..:timer.seconds(10)
      assert {:close, %State{garbled: 1}} = Stream.handle_info({:timeout, ref, :replace}, state)
    end

    test "does not reschedule or repeat the replacement for further garbled frames" do
      {:ok, state} = handle(@other_layout, state())
      %State{replace_timer: ref} = state

      state =
        Enum.reduce(1..5, state, fn _, state ->
          {:ok, %State{replace_timer: ^ref} = state} = handle(@other_layout, state)
          state
        end)

      assert Process.cancel_timer(ref) in 1..:timer.seconds(10)
      assert {:close, state} = Stream.handle_info({:timeout, ref, :replace}, state)

      disconnect = %{reason: {:local, :normal}, attempt_number: 1}

      assert {:reconnect, %State{replace_timer: nil, garbled: 1}} =
               Stream.handle_disconnect(disconnect, state)
    end

    test "waits longer with every replacement in a row, from 10 s up to 30 s" do
      for {garbled, seconds} <- [{0, 10}, {3, 10}, {4, 16}, {5, 30}, {9, 30}] do
        {:ok, %State{replace_timer: ref}} = handle(@other_layout, state(garbled: garbled))
        ms = :timer.seconds(seconds)

        assert Process.cancel_timer(ref) in (ms - 100)..ms
      end
    end

    test "a valid frame cancels the replacement and resets the delay" do
      {:ok, state} = handle(@other_layout, state(garbled: 3))
      %State{replace_timer: ref} = state

      {:ok, state} = handle(@subscribed, state)

      assert_received {:received, %Data{soc: 67}}
      assert %State{replace_timer: nil, garbled: 0} = state
      assert Process.read_timer(ref) == false
      assert {:ok, ^state} = Stream.handle_info({:timeout, ref, :replace}, state)
    end

    test "leaves resubscribing after vehicle_disconnected to its backoff" do
      {:ok, state} = handle(@other_layout, state())
      %State{replace_timer: ref} = state

      msg =
        Jason.encode!(%{
          "msg_type" => "data:error",
          "tag" => "#{@vid}",
          "error_type" => "vehicle_disconnected"
        })

      {:ok, state} = Stream.handle_frame({:text, msg}, state)

      assert %State{replace_timer: nil, disconnects: 1} = state
      assert Process.read_timer(ref) == false
      assert Process.cancel_timer(state.timer) > 0
    end
  end
end
