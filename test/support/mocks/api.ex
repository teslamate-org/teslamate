defmodule ApiMock do
  use GenServer

  defmodule State do
    defstruct [:pid, :events, :pending_vehicle_data, :receiver, :vehicle]
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def get_vehicle(name, id), do: GenServer.call(name, {:get_vehicle, id})
  def get_vehicle_with_state(name, id), do: GenServer.call(name, {:get_vehicle_with_state, id})
  def stream(name, vid, receiver), do: GenServer.call(name, {:stream, vid, receiver})

  def sign_in(name, tokens), do: GenServer.call(name, {:sign_in, tokens})

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

  defp exec(event, _action) when is_function(event), do: event.()
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
