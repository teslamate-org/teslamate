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

    def get_vehicle(name \\ @name, id) do
      GenServer.call(name, {:get_vehicle, id})
    end

    def get_vehicle_with_state(name \\ @name, id) do
      GenServer.call(name, {:get_vehicle_with_state, id})
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
          %Error{error: :vehicle_unavailable} -> {:error, :unavailable}
          %Error{message: reason} -> {:error, reason}
          %Vehicle{} = vehicle -> {:ok, vehicle}
        end

      {:reply, response, state}
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

    # Private

    defp do_list_vehicles(auth) do
      case Vehicle.list(auth) do
        vehicles when is_list(vehicles) -> {:ok, vehicles}
        %Error{message: reason} -> {:error, reason}
      end
    end

    defp find_vehicle(vehicles, id) do
      case Enum.find(vehicles, &match?(%Vehicle{id: ^id}, &1)) do
        nil -> {:error, :vehicle_not_found}
        vehicle -> {:ok, vehicle}
      end
    end
  else
    # API

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
    end

    def get_vehicle(_id) do
      {:ok, vehicles} = list_vehicles()
      {:ok, hd(vehicles)}
    end

    def get_vehicle_with_state(_id) do
      # {:error, :unavailable}

      {:ok,
       %Vehicle{
         state: "online",
         charge_state: %Vehicle.State.Charge{
           # timestamp: DateTime.utc_now() |> DateTime.to_unix(:microsecond),
           # charging_state: "Unplugged",
           # charger_power: 22,
           # battery_level: 16,
           # charge_energy_added: 0.5,
           # ideal_battery_range: 59.95
         },
         drive_state: %Vehicle.State.Drive{
           timestamp: DateTime.utc_now() |> DateTime.to_unix(:microsecond),
           # shift_state: "N",
           # speed: 50,
           latitude: 0.0,
           longitude: 0.0
         },
         climate_state: %Vehicle.State.Climate{},
         vehicle_state: %Vehicle.State.VehicleState{}
       }}
    end

    def list_vehicles do
      m3 = %Vehicle{
        id: 1000,
        state: "online",
        vehicle_id: 1010,
        display_name: "Tesla!M3",
        option_codes: ["MDL3", "BT37", "DV4W"]
      }

      {:ok, [m3]}
    end

    @impl true
    def init(_opts) do
      {:ok, nil}
    end
  end
end
