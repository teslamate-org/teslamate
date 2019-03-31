defmodule TeslaMate.Api do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]
  alias TeslaApi.{Auth, Error, Vehicle}

  defstruct auth: nil,
            deps: %{}

  alias __MODULE__, as: State

  @name __MODULE__

  if Mix.env() === :prod do
    # API

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
    end

    def list_vehicles(name \\ @name) do
      GenServer.call(name, :list_vehicles)
    end

    def charge_state(name \\ @name, vehicle_id) do
      GenServer.call(name, {:charge_state, vehicle_id})
    end

    # Callbacks

    @impl true
    def init(opts) do
      username = Keyword.fetch!(opts, :username)
      password = Keyword.fetch!(opts, :password)

      case Auth.login(username, password) do
        %Error{error: error, message: reason, env: _env} ->
          Logger.error("Login failed: #{inspect({error, reason})}")
          {:stop, {error, reason}}

        %Auth{} = auth ->
          Logger.info("Login successful")
          {:ok, %State{auth: auth}, {:continue, :schedule_refresh}}
      end
    end

    @impl true
    def handle_call({:charge_state, vehicle_id}, _from, state) do
      case Vehicle.State.charge_state(state.auth, vehicle_id) do
        %Vehicle.State.Charge{} = charge_state -> {:reply, charge_state, state}
        %Error{message: reason} -> {:reply, {:error, reason}, state}
      end
    end

    def handle_call(:list_vehicles, _from, state) do
      case Vehicle.list(state.auth) do
        vehicles when is_list(vehicles) -> {:reply, {:ok, vehicles}, state}
        %Error{message: reason} -> {:reply, {:error, reason}, state}
      end
    end

    @impl true
    def handle_info(:refresh_auth, %State{auth: auth} = state) do
      case Auth.refresh(auth) do
        %Auth{} = auth -> {:noreply, %State{state | auth: auth}, {:continue, :schedule_refresh}}
        %Error{error: error, message: reason, env: _} -> {:stop, {error, reason}}
      end
    end

    @impl true
    def handle_continue(:schedule_refresh, state) do
      Process.send_after(self(), :refresh_auth, :timer.hours(24 * 30))
      {:noreply, state}
    end
  else
    # API

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
    end

    def charge_state(vehicle_id) do
      {:ok, %Vehicle.State.Charge{}}
    end

    def list_vehicles do
      {:ok,
       [%Vehicle{vehicle_id: 0, display_name: "Tesla!M3", option_codes: ["MDL3", "BT37", "DV4W"]}]}
    end

    @impl true
    def init(opts) do
      {:ok, nil}
    end
  end
end
