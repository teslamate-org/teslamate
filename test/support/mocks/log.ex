defmodule LogMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  alias TeslaMate.Log.{Trip, ChargingProcess, Update}

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def start_state(name, car_id, state), do: GenServer.call(name, {:start_state, car_id, state})

  def start_trip(name, car_id), do: GenServer.call(name, {:start_trip, car_id})
  def close_trip(name, trip_id), do: GenServer.call(name, {:close_trip, trip_id})

  def start_update(name, car_id), do: GenServer.call(name, {:start_update, car_id})
  def cancel_update(name, update_id), do: GenServer.call(name, {:cancel_update, update_id})

  def finish_update(name, update_id, version),
    do: GenServer.call(name, {:finish_update, update_id, version})

  def start_charging_process(name, car_id, position_attrs) do
    GenServer.call(name, {:start_charging_process, car_id, position_attrs})
  end

  def close_charging_process(name, process_id) do
    GenServer.call(name, {:close_charging_process, process_id})
  end

  def insert_position(name, car_id, attrs) do
    GenServer.call(name, {:insert_position, car_id, attrs})
  end

  def insert_charge(name, car_id, attrs) do
    GenServer.call(name, {:insert_charge, car_id, attrs})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:start_charging_process, _cid, _pos} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 99}, state}
  end

  def handle_call({:close_charging_process, _pid} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %ChargingProcess{}}, state}
  end

  def handle_call({:start_trip, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 111}, state}
  end

  def handle_call({:close_trip, _trip_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Trip{}}, state}
  end

  def handle_call({:start_update, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 111}, state}
  end

  def handle_call({:cancel_update, _update_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Update{}}, state}
  end

  def handle_call({:finish_update, _upd_id, _version} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Update{}}, state}
  end

  def handle_call(action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, :ok, state}
  end
end
