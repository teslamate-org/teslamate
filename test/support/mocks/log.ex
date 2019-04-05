defmodule LogMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  alias TeslaMate.Log.{Trip, Car}

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_car_by_eid(name, eid), do: GenServer.call(name, {:get_car_by_eid, eid})
  def create_car(name, car), do: GenServer.call(name, {:create_car, car})

  def start_state(name, car_id, state), do: GenServer.call(name, {:start_state, car_id, state})

  def start_trip(name, car_id), do: GenServer.call(name, {:start_trip, car_id})
  def close_trip(name, trip_id), do: GenServer.call(name, {:close_trip, trip_id})

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
  def handle_call({:get_car_by_eid, _eid}, _from, state) do
    {:reply, nil, state}
  end

  def handle_call({:create_car, car}, _from, state) do
    {:reply, {:ok, struct(Car, Map.put(car, :id, 999))}, state}
  end

  def handle_call({:start_charging_process, _cid, _pos} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 99}, state}
  end

  def handle_call({:start_trip, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 111}, state}
  end

  def handle_call({:close_trip, _trip_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Trip{}}, state}
  end

  def handle_call(action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, :ok, state}
  end
end
