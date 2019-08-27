defmodule LogMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  alias TeslaMate.Log.{Drive, ChargingProcess, Update}
  alias TeslaMate.Log

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def start_state(name, car_id, state), do: GenServer.call(name, {:start_state, car_id, state})
  def get_current_state(name, car_id), do: GenServer.call(name, {:get_current_state, car_id})

  def start_drive(name, car_id), do: GenServer.call(name, {:start_drive, car_id})
  def close_drive(name, drive_id), do: GenServer.call(name, {:close_drive, drive_id})

  def start_update(name, car_id), do: GenServer.call(name, {:start_update, car_id})
  def cancel_update(name, update_id), do: GenServer.call(name, {:cancel_update, update_id})

  def finish_update(name, update_id, version),
    do: GenServer.call(name, {:finish_update, update_id, version})

  def start_charging_process(name, car_id, position_attrs, opts \\ []) do
    GenServer.call(name, {:start_charging_process, car_id, position_attrs, opts})
  end

  def resume_charging_process(name, process_id) do
    GenServer.call(name, {:resume_charging_process, process_id})
  end

  def complete_charging_process(name, process_id, opts \\ []) do
    GenServer.call(name, {:complete_charging_process, process_id, opts})
  end

  def insert_position(name, car_id, attrs) do
    GenServer.call(name, {:insert_position, car_id, attrs})
  end

  def insert_charge(name, car_id, attrs) do
    GenServer.call(name, {:insert_charge, car_id, attrs})
  end

  def get_positions_without_elevation(name, min_id) do
    GenServer.call(name, {:get_positions_without_elevation, min_id})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:start_state, _car_id, s} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Log.State{state: s, start_date: DateTime.utc_now()}}, state}
  end

  def handle_call({:get_current_state, _}, _from, state) do
    {:reply, {:ok, %Log.State{state: :online, start_date: DateTime.from_unix!(0)}}, state}
  end

  def handle_call({:start_charging_process, _, _, _} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 99}, state}
  end

  def handle_call({:resume_charging_process, _pid} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %ChargingProcess{}}, state}
  end

  def handle_call({:complete_charging_process, _, _} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %ChargingProcess{charge_energy_added: 45}}, state}
  end

  def handle_call({:start_drive, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, 111}, state}
  end

  def handle_call({:close_drive, _drive_id} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, {:ok, %Drive{duration_min: 10, distance: 20.0}}, state}
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

  def handle_call({:get_positions_without_elevation, _} = action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, [], state}
  end

  def handle_call(action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, :ok, state}
  end
end
