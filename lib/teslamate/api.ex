defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias TeslaApi.{Auth, Error, Vehicle}

  defstruct auth: nil
  alias __MODULE__, as: State

  @name __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  ## State

  def list_vehicles(name \\ @name) do
    GenServer.call(name, :list_vehicles, 35_000)
  end

  def get_vehicle(name \\ @name, id) do
    GenServer.call(name, {:get_vehicle, id}, 35_000)
  end

  def get_vehicle_with_state(name \\ @name, id) do
    GenServer.call(name, {:get_vehicle_with_state, id}, 35_000)
  end

  ## Commands

  def wake_up(name \\ @name, id) do
    GenServer.call(name, {:wake_up, id}, 35_000)
  end

  # Callbacks

  @impl true
  def init(opts) do
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)

    case Auth.login(username, password) do
      {:ok, %Auth{} = auth} -> {:ok, %State{auth: auth}, {:continue, :schedule_refresh}}
      {:error, %Error{} = error} -> {:stop, error}
    end
  end

  @impl true
  def handle_call(:list_vehicles, _from, state) do
    {:reply, do_list_vehicles(state.auth), state}
  end

  def handle_call({:get_vehicle, id}, _from, state) do
    response =
      with {:ok, vehicles} <- do_list_vehicles(state.auth),
           {:ok, vehicle} <- find_vehicle(vehicles, id) do
        {:ok, vehicle}
      end

    {:reply, response, state}
  end

  def handle_call({:get_vehicle_with_state, id}, _from, state) do
    response =
      case Vehicle.get_with_state(state.auth, id) do
        {:error, %Error{error: :vehicle_unavailable}} -> {:error, :unavailable}
        {:error, %Error{} = error} -> {:error, error}
        {:ok, %Vehicle{} = vehicle} -> {:ok, vehicle}
      end

    {:reply, response, state}
  end

  def handle_call({:wake_up, id}, _from, state) do
    response =
      case Vehicle.Command.wake_up(state.auth, id) do
        {:ok, %Vehicle{state: "online"}} -> :ok
        {:ok, %Vehicle{state: _other}} -> {:error, :unavailable}
        {:error, %Error{error: :vehicle_unavailable}} -> {:error, :unavailable}
        {:error, %Error{} = error} -> {:error, error}
      end

    {:reply, response, state}
  end

  @impl true
  def handle_info(:refresh_auth, %State{auth: auth} = state) do
    case Auth.refresh(auth) do
      {:ok, %Auth{} = auth} ->
        {:noreply, %State{state | auth: auth}, {:continue, :schedule_refresh}}

      {:error, %Error{error: error, message: reason, env: _}} ->
        {:stop, {error, reason}}
    end
  end

  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_continue(:schedule_refresh, %State{auth: auth} = state) do
    ms =
      auth.expires_in
      |> Kernel.*(0.9)
      |> round()
      |> :timer.seconds()

    Process.send_after(self(), :refresh_auth, ms)

    {:noreply, state}
  end

  # Private

  defp do_list_vehicles(auth) do
    with %Error{message: reason, env: env} <- Vehicle.list(auth) do
      {:error, {reason, env}}
    end
  end

  defp find_vehicle(vehicles, id) do
    case Enum.find(vehicles, &match?(%Vehicle{id: ^id}, &1)) do
      nil -> {:error, :vehicle_not_found}
      vehicle -> {:ok, vehicle}
    end
  end
end
