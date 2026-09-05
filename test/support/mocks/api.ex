defmodule ApiMock do
  use GenServer

  defmodule State do
    defstruct [
      :pid,
      :events,
      :pending_vehicle_data,
      :receiver,
      :vehicle,
      :last_served,
      calls: [],
      interactions: []
    ]
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

  # Interactions with neighbouring systems that leave neither a row nor a
  # topic — stream connect/disconnect, the supervisor kill — each tagged
  # with the index of the API event served last (see :indexed events).
  def interactions(name), do: GenServer.call(name, :interactions)
  def record_interaction(name, interaction), do: GenServer.call(name, {:record, interaction})

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
    %State{} = state = mark_served(state, event)

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

  def handle_call(:interactions, _from, %State{interactions: interactions} = state) do
    {:reply, Enum.reverse(interactions), state}
  end

  def handle_call({:record, interaction}, _from, state) do
    {:reply, :ok, note_interaction(state, interaction)}
  end

  def handle_call({:sign_in, _tokens} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, :ok, state}
  end

  # In a characterization replay (the :vehicle option is set) the mock is
  # the stream: the vehicle's Stream.disconnect/1 cast then lands here
  # (handle_info below) and is recorded like the connect. Mock-based tests
  # keep the test process as the stream pid and see the cast themselves.
  def handle_call({:stream, _vid, receiver} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    stream_pid = if state.vehicle, do: self(), else: pid

    {:reply, {:ok, stream_pid},
     %State{state | receiver: receiver} |> note_interaction({:stream, :connect})}
  end

  @impl true
  def handle_info({:"$websockex_cast", :disconnect}, state) do
    {:noreply, note_interaction(state, {:stream, :disconnect})}
  end

  defp note_interaction(%State{interactions: acc, last_served: served} = state, interaction),
    do: %State{state | interactions: [{served, interaction} | acc]}

  # Characterization events arrive as {:indexed, index, closure}: the index
  # is the collector's serve index, so a snapshot's probe and strict serve
  # carry the same one.
  defp mark_served(%State{} = state, {:snapshot, event}), do: mark_served(state, event)

  defp mark_served(%State{} = state, {:indexed, index, _fun}),
    do: %State{state | last_served: index}

  defp mark_served(%State{} = state, _event), do: state

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
    await_call_outcome(proxy, :suspend_logging, state, nil)
  end

  defp deliver_call(:resume_logging, %State{vehicle: vehicle} = state) do
    proxy = Task.async(fn -> TeslaMate.Vehicles.Vehicle.resume_logging(vehicle) end)
    await_call_outcome(proxy, :resume_logging, state, nil)
  end

  # The summary is a value, not an effect: the proxy returns it and the
  # struct is recorded as the call's reply.
  defp deliver_call(:summary, %State{vehicle: vehicle} = state) do
    proxy = Task.async(fn -> TeslaMate.Vehicles.Vehicle.summary(vehicle) end)
    await_call_outcome(proxy, :summary, state, nil)
  end

  # The production path minus the PubSub hop: Settings.update_car_settings/2
  # validates and writes the car_settings row; the persisted struct is then
  # sent to the vehicle exactly as its subscription would deliver it (the
  # SettingsMock replaces that subscription), and get_state proves the
  # vehicle applied it before the next API event is served.
  defp deliver_call({:update_car_settings, attrs}, %State{vehicle: vehicle} = state) do
    proxy =
      Task.async(fn ->
        {_state, %{car: car}} = :sys.get_state(vehicle)
        pre = %{car.settings | car: car}

        case TeslaMate.Settings.update_car_settings(pre, attrs) do
          {:ok, post} ->
            send(vehicle, post)
            :sys.get_state(vehicle)
            :ok

          {:error, %Ecto.Changeset{}} = rejection ->
            rejection
        end
      end)

    await_call_outcome(proxy, :update_car_settings, state, nil)
  end

  defp await_call_outcome(
         %Task{ref: ref} = proxy,
         call,
         %State{events: [event | _]} = state,
         last
       ) do
    receive do
      {:"$gen_call", from, {action, _id}}
      when action in [:get_vehicle, :get_vehicle_with_state] ->
        # The vehicle's synchronous strict fetch inside the call handler —
        # answered from the queue through the regular exec path, so the serve
        # counts like any other (index, barrier, vacuity).
        result = exec(event, action)
        GenServer.reply(from, result)
        %State{} = state = mark_served(state, event)
        await_call_outcome(proxy, call, advance_event(state), result)

      {^ref, :ok} ->
        Process.demonitor(ref, [:flush])
        state = record_call(state, call, :ok)

        # Only a suspend that went through its strict fetch dooms the parked
        # poll; :ok on an already suspended, asleep or offline vehicle is a
        # no-op whose caller keeps its task.
        case :sys.get_state(state.vehicle) do
          {{:suspended, _}, _data} when last != nil -> {:suspended, last, state}
          _ -> {:continue, state}
        end

      {^ref, %TeslaMate.Vehicles.Vehicle.Summary{} = summary} ->
        Process.demonitor(ref, [:flush])
        {:continue, record_call(state, call, summary)}

      {^ref, {:error, _reason} = rejection} ->
        # A rejection is outer behaviour — recorded into the golden's calls
        # section, not a harness error.
        Process.demonitor(ref, [:flush])
        {:continue, record_call(state, call, rejection)}

      {:DOWN, ^ref, :process, _pid, reason} ->
        raise "the #{call} call proxy died: #{inspect(reason)}"
    after
      5_000 ->
        raise "the declared #{call} call did not complete within 5s"
    end
  end

  defp record_call(%State{calls: calls} = state, call, reply),
    do: %State{state | calls: [{call, reply} | calls]}

  # Events tagged with :get_vehicle or :get_vehicle_with_state may only be
  # consumed by that API call, allowing tests to pin which endpoint was used.
  defp exec({:snapshot, event}, action), do: exec(event, action)
  defp exec({:indexed, _index, fun}, action), do: exec(fun, action)

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
