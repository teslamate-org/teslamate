defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias TeslaMate.Auth.{Tokens, Credentials}
  alias TeslaMate.Vehicles
  alias TeslaApi.Auth

  alias Mojito.Response

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct name: nil, deps: %{}
  alias __MODULE__, as: State

  @name __MODULE__

  # API

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, @name)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  ## State

  def list_vehicles(name \\ @name) do
    with {:ok, auth} <- fetch_auth(name) do
      TeslaApi.Vehicle.list(auth)
      |> handle_result(auth, name)
    end
  end

  def get_vehicle(name \\ @name, id) do
    with {:ok, auth} <- fetch_auth(name) do
      TeslaApi.Vehicle.get(auth, id)
      |> handle_result(auth, name)
    end
  end

  def get_vehicle_with_state(name \\ @name, id) do
    with {:ok, auth} <- fetch_auth(name) do
      TeslaApi.Vehicle.get_with_state(auth, id)
      |> handle_result(auth, name)
    end
  end

  ## Internals

  def signed_in?(name \\ @name) do
    case fetch_auth(name) do
      {:error, :not_signed_in} -> false
      {:ok, _} -> true
    end
  end

  def sign_in(name \\ @name, credentials) do
    case fetch_auth(name) do
      {:error, :not_signed_in} -> GenServer.call(name, {:sign_in, credentials}, 15_000)
      {:ok, %Auth{}} -> {:error, :already_signed_in}
    end
  end

  # Callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    deps = %{
      auth: Keyword.get(opts, :auth, TeslaMate.Auth),
      vehicles: Keyword.get(opts, :vehicles, Vehicles)
    }

    ^name = :ets.new(name, [:named_table, :set, :public, read_concurrency: true])

    with %Tokens{access: at, refresh: rt} <- call(deps.auth, :get_tokens),
         {:ok, %Auth{} = auth} <- Auth.refresh(%Auth{token: at, refresh_token: rt}) do
      Logger.info("Refreshed api tokens")
      :ok = call(deps.auth, :save, [auth])
      true = insert_auth(name, auth)
      :ok = schedule_refresh(auth)
    else
      {:error, reason} -> Logger.warn("Token refresh failed: #{inspect(reason, pretty: true)}")
      nil -> nil
    end

    {:ok, %State{name: name, deps: deps}}
  end

  @impl true
  def handle_call({:sign_in, %Credentials{email: email, password: password}}, _from, state) do
    case Auth.login(email, password) do
      {:ok, %Auth{} = auth} ->
        true = insert_auth(state.name, auth)
        :ok = call(state.deps.auth, :save, [auth])
        :ok = call(state.deps.vehicles, :restart)
        :ok = schedule_refresh(auth)
        {:reply, :ok, state}

      {:error, %TeslaApi.Error{reason: reason}} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:refresh_auth, %State{name: name} = state) do
    Logger.info("Refreshing access token ...")

    {:ok, auth} = fetch_auth(name)
    {:ok, auth} = Auth.refresh(auth)

    true = insert_auth(name, auth)
    :ok = call(state.deps.auth, :save, [auth])
    :ok = schedule_refresh(auth)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("#{__MODULE__} / unhandled message: #{inspect(msg, pretty: true)}")
    {:noreply, state}
  end

  ## Private

  defp schedule_refresh(%Auth{} = auth) do
    ms =
      auth.expires_in
      |> Kernel.*(0.89)
      |> round()
      |> :timer.seconds()

    Logger.info("Scheduling token refresh in #{round(ms / (24 * 60 * 60 * 1000))}d")
    Process.send_after(self(), :refresh_auth, ms)

    :ok
  end

  defp insert_auth(name, %Auth{} = auth) do
    :ets.insert(name, auth: auth)
  end

  defp fetch_auth(name) do
    case :ets.lookup(name, :auth) do
      [auth: %Auth{} = auth] -> {:ok, auth}
      [] -> {:error, :not_signed_in}
    end
  rescue
    _ in ArgumentError -> {:error, :not_signed_in}
  end

  defp handle_result(result, auth, name) do
    case result do
      {:error, %TeslaApi.Error{reason: :unauthorized}} ->
        true = :ets.delete(name, :auth)
        {:error, :not_signed_in}

      {:error, %TeslaApi.Error{reason: reason, env: %Response{status_code: status, body: body}}} ->
        Logger.error("TeslaApi.Error / #{status} – #{inspect(body, pretty: true)}")
        {:error, reason}

      {:error, %TeslaApi.Error{reason: reason, message: msg}} ->
        if is_binary(msg) and msg != "", do: Logger.warn("TeslaApi.Error / #{msg}")
        {:error, reason}

      {:ok, vehicles} when is_list(vehicles) ->
        vehicles =
          vehicles
          |> Task.async_stream(&preload_vehicle(&1, auth), timeout: 32_500)
          |> Enum.map(fn {:ok, vehicle} -> vehicle end)

        {:ok, vehicles}

      {:ok, %TeslaApi.Vehicle{} = vehicle} ->
        {:ok, vehicle}
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{state: "online", id: id} = vehicle, auth) do
    case TeslaApi.Vehicle.get_with_state(auth, id) do
      {:ok, %TeslaApi.Vehicle{} = vehicle} ->
        vehicle

      {:error, reason} ->
        Logger.warn("TeslaApi.Error / #{inspect(reason, pretty: true)}")
        vehicle
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{} = vehicle, _state), do: vehicle
end
