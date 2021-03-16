defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias TeslaMate.Auth.{Tokens, Credentials}
  alias TeslaMate.{Vehicles, Convert}
  alias TeslaApi.Auth

  alias Finch.Response

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct name: nil, deps: %{}
  alias __MODULE__, as: State

  @timeout :timer.minutes(2)
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

  def stream(name \\ @name, vid, receiver) do
    with {:ok, %Auth{} = auth} <- fetch_auth(name) do
      TeslaApi.Stream.start_link(auth: auth, vehicle_id: vid, receiver: receiver)
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
      {:error, :not_signed_in} -> GenServer.call(name, {:sign_in, [credentials]}, @timeout)
      {:ok, %Auth{}} -> {:error, :already_signed_in}
    end
  end

  def sign_in(name \\ @name, device_id, mfa_passcode, %Auth.MFA.Ctx{} = ctx) do
    case fetch_auth(name) do
      {:error, :not_signed_in} ->
        GenServer.call(name, {:sign_in, [device_id, mfa_passcode, ctx]}, @timeout)

      {:ok, %Auth{}} ->
        {:error, :already_signed_in}
    end
  end

  def sign_out(name \\ @name) do
    true = :ets.delete(name, :auth)
    :ok
  rescue
    _ in ArgumentError -> {:error, :not_signed_in}
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

    with %Tokens{access: at, refresh: rt} when is_binary(at) and is_binary(rt) <-
           call(deps.auth, :get_tokens) do
      restored_tokens = %Auth{token: at, refresh_token: rt, expires_in: 1.12 * 60 * 60}

      case refresh_tokens(restored_tokens) do
        {:ok, refreshed_tokens} ->
          :ok = call(deps.auth, :save, [refreshed_tokens])
          true = insert_auth(name, refreshed_tokens)
          :ok = schedule_refresh(refreshed_tokens)

        {:error, reason} ->
          Logger.warning("Token refresh failed: #{inspect(reason, pretty: true)}")
          true = insert_auth(name, restored_tokens)
          :ok = schedule_refresh(restored_tokens)
      end
    end

    {:ok, %State{name: name, deps: deps}}
  end

  @impl true
  def handle_call({:sign_in, args}, _, state) do
    case args do
      [%Credentials{} = c] -> Auth.login(c.email, c.password)
      [%Tokens{} = t] -> Auth.refresh(%Auth{token: t.access, refresh_token: t.refresh})
      [device_id, passcode, ctx] -> Auth.login(device_id, passcode, ctx)
    end
    |> case do
      {:ok, %Auth{} = auth} ->
        true = insert_auth(state.name, auth)
        :ok = call(state.deps.auth, :save, [auth])
        :ok = call(state.deps.vehicles, :restart)
        :ok = schedule_refresh(auth)
        {:reply, :ok, state}

      {:ok, {:mfa, _devices, _ctx} = mfa} ->
        {:reply, {:ok, mfa}, state}

      {:error, %TeslaApi.Error{} = e} ->
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_info(:refresh_auth, %State{name: name} = state) do
    case fetch_auth(name) do
      {:ok, tokens} ->
        Logger.info("Refreshing access token ...")

        case Auth.refresh(tokens) do
          {:ok, refreshed_tokens} ->
            true = insert_auth(name, refreshed_tokens)
            :ok = call(state.deps.auth, :save, [refreshed_tokens])
            :ok = schedule_refresh(refreshed_tokens)

          {:error, reason} ->
            Logger.warning("Token refresh failed: #{inspect(reason, pretty: true)}")
            Logger.warning("Retrying in 1 hour...")
            Process.send_after(self(), :refresh_auth, :timer.hours(1))
        end

      {:error, reason} ->
        Logger.warning("Cannot refresh access token: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("#{__MODULE__} / unhandled message: #{inspect(msg, pretty: true)}")
    {:noreply, state}
  end

  ## Private

  defp refresh_tokens(%Auth{} = tokens) do
    case Application.get_env(:teslamate, :disable_token_refresh, false) do
      true ->
        Logger.info("Token refresh is disabled")
        {:ok, tokens}

      false ->
        with {:ok, %Auth{} = refresh_tokens} <- Auth.refresh(tokens) do
          Logger.info("Refreshed api tokens")
          {:ok, refresh_tokens}
        end
    end
  end

  defp schedule_refresh(%Auth{} = auth) do
    ms =
      auth.expires_in
      |> Kernel.*(0.9)
      |> round()
      |> :timer.seconds()

    duration =
      ms
      |> div(1000)
      |> Convert.sec_to_str()
      |> Enum.reject(&String.ends_with?(&1, "s"))
      |> Enum.join(" ")

    Logger.info("Scheduling token refresh in #{duration}")
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

      {:error, %TeslaApi.Error{reason: reason, env: %Response{status: status, body: body}}} ->
        Logger.error("TeslaApi.Error / #{status} – #{inspect(body, pretty: true)}")
        {:error, reason}

      {:error, %TeslaApi.Error{reason: reason, message: msg}} ->
        if is_binary(msg) and msg != "", do: Logger.warning("TeslaApi.Error / #{msg}")
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
        Logger.warning("TeslaApi.Error / #{inspect(reason, pretty: true)}")
        vehicle
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{} = vehicle, _state), do: vehicle
end
