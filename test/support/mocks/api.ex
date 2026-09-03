defmodule ApiMock do
  use GenServer

  defmodule State do
    defstruct [:pid, :events, :pending_vehicle_data, :receiver, :vehicle, calls: []]
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def get_vehicle(name, id), do: GenServer.call(name, {:get_vehicle, id})
  def get_vehicle_with_state(name, id), do: GenServer.call(name, {:get_vehicle_with_state, id})
  def stream(name, vid, receiver), do: GenServer.call(name, {:stream, vid, receiver})

  def sign_in(name, tokens), do: GenServer.call(name, {:sign_in, tokens})

  # Replies of delivered user-action calls, in delivery order — the outer
  # behaviour of the action (what the UI would get back), captured by the
  # characterization harness.
  def calls(name), do: GenServer.call(name, :calls)

  # Callbacks

  @impl true
  def init(opts) do
    state = %State{
      pid: Keyword.fetch!(opts, :pid),
      events: Keyword.get(opts, :events, []),
      vehicle: Keyword.get(opts, :vehicle)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:get_vehicle_with_state, id},
        _from,
        %State{pending_vehicle_data: {id, result}} = state
      ) do
    {:reply, result, advance_event(state)}
  end

  # A stream event at the queue head is delivered at the serve boundary:
  # the fetch task is parked in this call while the vehicle is free, so the
  # get_state round trip proves the frame is processed before the API event
  # is served — deterministic interleaving without a wall-clock wait.
  def handle_call(
        {action, id},
        from,
        %State{events: [{:stream_delivery, payload} | events]} = state
      )
      when action in [:get_vehicle, :get_vehicle_with_state] do
    :ok = deliver_stream(payload, state)
    handle_call({action, id}, from, %State{state | events: events})
  end

  # A clock event advances the replay's clock at the serve boundary, before
  # the next API event is served — the vehicle reads the new time when it
  # processes that event.
  def handle_call({action, id}, from, %State{events: [{:clock_delivery, set} | events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    :ok = set.()
    handle_call({action, id}, from, %State{state | events: events})
  end

  # A declared user-action call (e.g. suspend_logging) is delivered at the
  # serve boundary through a proxy task: the vehicle's suspend handler calls
  # back into this mock synchronously (fetch_strict), so a blocking call from
  # here would deadlock. The selective receive answers that strict fetch from
  # the queue through the same exec path as any serve, then the proxy's reply
  # is the proof the call handler completed.
  def handle_call({action, id}, from, %State{events: [{:call_delivery, call} | events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    case deliver_call(call, %State{state | events: events}) do
      {:suspended, last_result, state} ->
        # The caller's fetch task is doomed: the vehicle reset its task on
        # suspending and will discard this reply by reference. Re-serve the
        # last payload instead of consuming a scenario event for a reply
        # nobody reads.
        {:reply, last_result, state}

      {:continue, state} ->
        handle_call({action, id}, from, state)
    end
  end

  def handle_call({action, id}, _from, %State{events: [event | _events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    result = exec(event, action)

    case {action, snapshot?(event), result} do
      {:get_vehicle, true, {:ok, %TeslaApi.Vehicle{state: "online"}}} ->
        {:reply, result, %State{state | pending_vehicle_data: {id, result}}}

      _ ->
        {:reply, result, advance_event(state)}
    end
  end

  def handle_call(:calls, _from, %State{calls: calls} = state) do
    {:reply, Enum.reverse(calls), state}
  end

  def handle_call({:sign_in, _tokens} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, :ok, state}
  end

  def handle_call({:stream, _vid, receiver} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, {:ok, pid}, %State{state | receiver: receiver}}
  end

  defp deliver_stream(_payload, %State{vehicle: nil}) do
    raise "stream deliveries require the :vehicle option on ApiMock — " <>
            "the serve boundary needs the vehicle process for its get_state sync"
  end

  defp deliver_stream(_payload, %State{receiver: nil}) do
    raise "stream event declared but the vehicle never connected the stream — " <>
            "place stream events after the API event that establishes the stream"
  end

  defp deliver_stream(payload, %State{receiver: receiver, vehicle: vehicle}) do
    receiver.(payload)
    :sys.get_state(vehicle)
    :ok
  end

  defp deliver_call(_call, %State{vehicle: nil}) do
    raise "call deliveries require the :vehicle option on ApiMock — " <>
            "the serve boundary needs the vehicle process to invoke the call on"
  end

  defp deliver_call(:suspend_logging, %State{vehicle: vehicle} = state) do
    proxy = Task.async(fn -> TeslaMate.Vehicles.Vehicle.suspend_logging(vehicle) end)
    await_call_outcome(proxy, state, nil)
  end

  defp await_call_outcome(%Task{ref: ref} = proxy, %State{events: [event | _]} = state, last) do
    receive do
      {:"$gen_call", from, {action, _id}}
      when action in [:get_vehicle, :get_vehicle_with_state] ->
        # The vehicle's synchronous strict fetch inside the call handler —
        # answered from the queue through the regular exec path, so the serve
        # counts like any other (index, barrier, vacuity).
        result = exec(event, action)
        GenServer.reply(from, result)
        await_call_outcome(proxy, advance_event(state), result)

      {^ref, :ok} ->
        Process.demonitor(ref, [:flush])
        state = record_call(state, :suspend_logging, :ok)

        # Only a suspend that went through its strict fetch dooms the parked
        # poll; :ok on an already suspended, asleep or offline vehicle is a
        # no-op whose caller keeps its task.
        case :sys.get_state(state.vehicle) do
          {{:suspended, _}, _data} when last != nil -> {:suspended, last, state}
          _ -> {:continue, state}
        end

      {^ref, {:error, _reason} = rejection} ->
        # A rejection is outer behaviour — recorded into the golden's calls
        # section, not a harness error.
        Process.demonitor(ref, [:flush])
        {:continue, record_call(state, :suspend_logging, rejection)}

      {:DOWN, ^ref, :process, _pid, reason} ->
        raise "the suspend_logging call proxy died: #{inspect(reason)}"
    after
      5_000 ->
        raise "the declared suspend_logging call did not complete within 5s"
    end
  end

  defp record_call(%State{calls: calls} = state, call, reply),
    do: %State{state | calls: [{call, reply} | calls]}

  # Events tagged with :get_vehicle or :get_vehicle_with_state may only be
  # consumed by that API call, allowing tests to pin which endpoint was used.
  defp exec({:snapshot, event}, action), do: exec(event, action)

  defp exec({expected_action, event}, action)
       when expected_action in [:get_vehicle, :get_vehicle_with_state] do
    if expected_action != action do
      raise "expected #{inspect(expected_action)} to be called, but got #{inspect(action)}"
    end

    exec(event, action)
  end

  # Characterization serve closures take the API action so the harness can
  # tell one fetch cycle (probe + strict fetch) from two.
  defp exec(event, action) when is_function(event, 1), do: event.(action)
  defp exec(event, _action) when is_function(event, 0), do: event.()
  defp exec(event, _action), do: event

  defp snapshot?({:snapshot, _event}), do: true

  defp snapshot?({action, event}) when action in [:get_vehicle, :get_vehicle_with_state],
    do: snapshot?(event)

  defp snapshot?(_event), do: false

  defp advance_event(%State{events: [_event]} = state),
    do: %State{state | pending_vehicle_data: nil}

  defp advance_event(%State{events: [_event | events]} = state),
    do: %State{state | events: events, pending_vehicle_data: nil}
end
