defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias TeslaMate.Auth.{Tokens, Credentials}
  alias TeslaMate.Auth
  alias TeslaMate.Vehicles

  alias Mojito.Response

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct auth: nil, deps: %{}, refs: %{}
  alias __MODULE__, as: State

  @name __MODULE__
  @timeout 65_000

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  ## State

  def list_vehicles(name \\ @name) do
    GenServer.call(name, :list, @timeout)
  end

  def get_vehicle(name \\ @name, id) do
    GenServer.call(name, {:get, id}, @timeout)
  end

  def get_vehicle_with_state(name \\ @name, id) do
    GenServer.call(name, {:get_with_state, id}, @timeout)
  end

  ## Internals

  def sign_in(name \\ @name, credentials) do
    GenServer.call(name, {:sign_in, credentials})
  end

  def signed_in?(name \\ @name) do
    GenServer.call(name, :signed_in?)
  end

  # Callbacks

  @impl true
  def init(opts) do
    deps = %{
      auth: Keyword.get(opts, :auth, Auth),
      vehicles: Keyword.get(opts, :vehicles, Vehicles),
      tesla_api_auth: Keyword.get(opts, :tesla_api_auth, TeslaApi.Auth),
      tesla_api_vehicle: Keyword.get(opts, :tesla_api_vehicle, TeslaApi.Vehicle)
    }

    {:ok, %State{deps: deps}, {:continue, :sign_in}}
  end

  @impl true
  def handle_call({:sign_in, %Credentials{}}, _from, %State{auth: auth} = state)
      when not is_nil(auth) do
    {:reply, {:error, :already_signed_in}, state}
  end

  def handle_call({:sign_in, %Credentials{email: email, password: password}}, _from, state) do
    case call(state.deps.tesla_api_auth, :login, [email, password]) do
      {:ok, %TeslaApi.Auth{} = auth} ->
        :ok = call(state.deps.auth, :save, [auth])
        :ok = call(state.deps.vehicles, :restart)
        {:reply, :ok, %State{state | auth: auth}, {:continue, :schedule_refresh}}

      {:error, %TeslaApi.Error{reason: reason}} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:signed_in?, _from, %State{auth: auth} = state) do
    {:reply, not is_nil(auth), state}
  end

  def handle_call(_command, _from, %State{auth: nil} = state) do
    {:reply, {:error, :not_signed_in}, state}
  end

  def handle_call(:list, from, state) do
    task =
      Task.async(fn ->
        {:list, call(state.deps.tesla_api_vehicle, :list, [state.auth])}
      end)

    {:noreply, %State{state | refs: Map.put(state.refs, task.ref, from)}}
  end

  def handle_call({cmd, id}, from, state) when cmd in [:get, :get_with_state] do
    task =
      Task.async(fn ->
        {cmd, call(state.deps.tesla_api_vehicle, cmd, [state.auth, id])}
      end)

    {:noreply, %State{state | refs: Map.put(state.refs, task.ref, from)}}
  end

  @impl true
  def handle_info({ref, {cmd, result}}, %State{refs: refs} = state)
      when cmd in [:list, :get, :get_with_state] do
    {reply, state} =
      case result do
        {:error, %TeslaApi.Error{reason: :unauthorized}} ->
          {{:error, :not_signed_in}, %State{state | auth: nil}}

        {:error, %TeslaApi.Error{reason: reason, env: %Response{status_code: status, body: body}}} ->
          Logger.error("TeslaApi.Error / #{status} – #{inspect(body, pretty: true)}")
          {{:error, reason}, state}

        {:error, %TeslaApi.Error{reason: reason, message: msg}} ->
          if is_binary(msg) and msg != "", do: Logger.warn("TeslaApi.Error / #{msg}")
          {{:error, reason}, state}

        {:ok, vehicles} when is_list(vehicles) ->
          vehicles =
            vehicles
            |> Task.async_stream(&preload_vehicle(&1, state), timeout: 32_500)
            |> Enum.map(fn {:ok, vehicle} -> vehicle end)

          {{:ok, vehicles}, state}

        {:ok, %TeslaApi.Vehicle{} = vehicle} ->
          {{:ok, vehicle}, state}
      end

    {from, refs} = Map.pop(refs, ref)
    GenServer.reply(from, reply)

    {:noreply, %State{state | refs: refs}}
  end

  def handle_info(:refresh_auth, state) do
    Logger.info("Refreshing access token ...")

    case call(state.deps.tesla_api_auth, :refresh, [state.auth]) do
      {:ok, %TeslaApi.Auth{} = auth} ->
        :ok = call(state.deps.auth, :save, [auth])
        {:noreply, %State{state | auth: auth}, {:continue, :schedule_refresh}}

      {:error, %TeslaApi.Error{reason: reason, message: message}} ->
        {:stop, {reason, message}}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:ssl_closed, _}, state), do: {:noreply, state}

  @impl true
  def handle_continue(:sign_in, %State{} = state) do
    with %Tokens{access: access, refresh: refresh} <- call(state.deps.auth, :get_tokens),
         api_auth = %TeslaApi.Auth{token: access, refresh_token: refresh},
         {:ok, %TeslaApi.Auth{} = auth} <- call(state.deps.tesla_api_auth, :refresh, [api_auth]) do
      Logger.info("Refreshed api tokens")
      :ok = call(state.deps.auth, :save, [auth])
      {:noreply, %State{state | auth: auth}, {:continue, :schedule_refresh}}
    else
      nil ->
        Logger.info("Please sign in")
        {:noreply, state}

      {:error, %TeslaApi.Error{} = error} ->
        Logger.warn("Please sign in again.\n\n" <> inspect(error, pretty: true))
        {:noreply, state}
    end
  end

  def handle_continue(:schedule_refresh, %State{auth: auth} = state) do
    ms =
      auth.expires_in
      |> Kernel.*(0.8)
      |> round()
      |> :timer.seconds()

    Logger.info("Scheduling token refresh in #{round(ms / (24 * 60 * 60 * 1000))}d")
    Process.send_after(self(), :refresh_auth, ms)

    {:noreply, state}
  end

  ## Private

  defp preload_vehicle(%TeslaApi.Vehicle{state: "online", id: id} = vehicle, state) do
    case call(state.deps.tesla_api_vehicle, :get_with_state, [state.auth, id]) do
      {:ok, %TeslaApi.Vehicle{} = vehicle} ->
        vehicle

      {:error, reason} ->
        Logger.warn("TeslaApi.Error / #{inspect(reason, pretty: true)}")
        vehicle
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{} = vehicle, _state), do: vehicle
end
