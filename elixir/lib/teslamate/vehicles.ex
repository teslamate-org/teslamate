defmodule TeslaMate.Vehicles do
  @moduledoc """
  Owns the vehicle loggers.

  This process holds the start options and a linked, unnamed supervisor with
  one `TeslaMate.Vehicles.Vehicle` child per car whose data collection is
  enabled. It is the only place that turns a `Car` into a child spec, both at
  start-up and when `discover/0` adds vehicles later. It does no database
  work itself: the caller of `discover/0` persists the vehicle and hands the
  owner a `%Car{}`, so a failing database call stays with that caller.

  ## Shutdown semantics

  The owner traps exits. `GenServer.stop/3` on it (see `restart/0`) stops the
  supervisor synchronously in `terminate/2`, so when the owner is gone every
  vehicle process is gone too. Its child spec has `shutdown: :infinity`, so
  the application supervisor waits for that: each vehicle gets its own
  shutdown time to close the open drive or charge instead of being killed
  after a fixed timeout. If the supervisor exits on its own, e.g. after
  exceeding its restart intensity, or is killed (see `kill/0`), the owner
  stops with the same reason and its parent restarts it, which repeats the
  vehicle discovery.
  """
  use GenServer, shutdown: :infinity

  require Logger

  alias __MODULE__.Vehicle
  alias TeslaMate.Log
  alias TeslaMate.Log.Car
  alias TeslaMate.Settings.CarSettings

  defstruct [:supervisor, :vehicle]
  alias __MODULE__, as: State

  @name __MODULE__
  @topic "vehicles"

  @typedoc """
  Result of a discovery. `{:ok, cars}` lists the cars whose logger was
  started by this call; cars already running or with data collection
  disabled are not in it. `{:error, :no_vehicles}` means the Tesla account
  contains no vehicle. The other errors come from the API call, or from
  persisting or starting a vehicle, in which case loggers started earlier in
  the same call keep running.
  """
  @type discovery ::
          {:ok, [Car.t()]}
          | {:error,
             :no_vehicles | :not_signed_in | :too_many_request | Ecto.Changeset.t() | term}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def list do
    display_order =
      Log.list_car_ids_by_display_order()
      |> Enum.with_index()
      |> Map.new()

    supervisor()
    |> Supervisor.which_children()
    |> Task.async_stream(fn {_, pid, _, _} -> Vehicle.summary(pid) end,
      ordered: false,
      max_concurrency: 10,
      timeout: 5000
    )
    |> Enum.map(fn {:ok, vehicle} -> vehicle end)
    # Summary.car.display_priority is stale by design: each vehicle process keeps
    # the Car it loaded at start, so the order has to come from the database instead.
    |> Enum.sort_by(fn %Vehicle.Summary{car: %Car{id: id}} ->
      {Map.get(display_order, id, map_size(display_order)), id}
    end)
  end

  @doc """
  Fetches the vehicle list from the Tesla API once and starts a logger for
  every vehicle that has none yet. Running loggers are untouched; vehicles
  that disappeared from the account are not stopped. Subscribers (see
  `subscribe/0`) receive `{TeslaMate.Vehicles, :vehicles_changed}` when at
  least one logger was started.
  """
  @spec discover() :: discovery
  def discover do
    case TeslaMate.Api.list_vehicles() do
      {:ok, []} -> {:error, :no_vehicles}
      {:ok, vehicles} -> start_missing(vehicles)
      {:error, :too_many_request, _retry_after} -> {:error, :too_many_request}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Subscribes the caller to `{TeslaMate.Vehicles, :vehicles_changed}` messages."
  def subscribe do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)
  end

  def kill do
    Logger.warning("Restarting #{__MODULE__} supervisor")
    supervisor() |> Process.exit(:kill)
  end

  def restart do
    with :ok <- GenServer.stop(@name, :normal),
         :ok <- block_until_started(250) do
      :ok
    end
  end

  defdelegate summary(id), to: Vehicle
  defdelegate resume_logging(id), to: Vehicle
  defdelegate suspend_logging(id), to: Vehicle
  defdelegate subscribe_to_summary(id), to: Vehicle
  defdelegate subscribe_to_fetch(id), to: Vehicle

  # Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    vehicle = Keyword.get(opts, :vehicle, Vehicle)

    children =
      opts
      |> Keyword.get_lazy(:vehicles, &list_vehicles!/0)
      |> Enum.map(&create_or_update!/1)
      |> Enum.uniq_by(fn %Car{id: id} -> id end)
      |> Enum.filter(fn %Car{settings: settings} -> settings.enabled end)
      |> Enum.map(fn car ->
        log_start(car)
        child_spec(vehicle, car)
      end)

    {:ok, supervisor} =
      Supervisor.start_link(children,
        strategy: :one_for_one,
        max_restarts: 5,
        max_seconds: 60
      )

    {:ok, %State{supervisor: supervisor, vehicle: vehicle}}
  end

  @impl true
  def handle_call(:supervisor, _from, %State{supervisor: supervisor} = state) do
    {:reply, supervisor, state}
  end

  def handle_call({:start_vehicle, %Car{} = car}, _from, %State{} = state) do
    %State{supervisor: supervisor, vehicle: module} = state

    reply =
      case Supervisor.start_child(supervisor, child_spec(module, car)) do
        {:ok, _pid} ->
          log_start(car)
          {:ok, :started}

        {:error, {:already_started, _pid}} ->
          {:ok, :running}

        {:error, reason} ->
          {:error, reason}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:EXIT, supervisor, reason}, %State{supervisor: supervisor} = state) do
    {:stop, reason, %State{state | supervisor: nil}}
  end

  @impl true
  def terminate(reason, %State{supervisor: supervisor}) when is_pid(supervisor) do
    Supervisor.stop(supervisor, reason)
  end

  def terminate(_reason, %State{supervisor: nil}), do: :ok

  # Private

  defp supervisor, do: GenServer.call(@name, :supervisor)

  defp child_spec(vehicle, %Car{} = car), do: {vehicle, car: car}

  defp log_start(%Car{name: nil}), do: :ok
  defp log_start(%Car{name: name}), do: Logger.info("Starting logger for '#{name}'")

  defp start_missing(vehicles) do
    {result, started} =
      Enum.reduce_while(vehicles, {:ok, []}, fn vehicle, {:ok, started} ->
        case start_vehicle_of(vehicle) do
          {:ok, :started, car} -> {:cont, {:ok, [car | started]}}
          {:ok, _running_or_disabled} -> {:cont, {:ok, started}}
          {:error, reason} -> {:halt, {{:error, reason}, started}}
        end
      end)
      |> case do
        {:ok, started} -> {:ok, started}
        {{:error, reason}, started} -> {{:error, reason}, started}
      end

    # Loggers started before a later vehicle failed are running and announced
    if started != [] do
      :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, @topic, {__MODULE__, :vehicles_changed})
    end

    case result do
      :ok -> {:ok, Enum.reverse(started)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_vehicle_of(%TeslaApi.Vehicle{} = vehicle) do
    case create_or_update(vehicle) do
      {:ok, %Car{} = car} ->
        start_vehicle_of_car(car)

      # A concurrent discovery inserted the car between the lookup and the
      # insert; the second attempt finds and updates it.
      {:error, %Ecto.Changeset{errors: errors}} = error ->
        retry_after_unique_violation(vehicle, unique_violation?(errors), error)
    end
  end

  defp retry_after_unique_violation(vehicle, true, _error) do
    with {:ok, %Car{} = car} <- create_or_update(vehicle), do: start_vehicle_of_car(car)
  end

  defp retry_after_unique_violation(_vehicle, false, error), do: error

  defp start_vehicle_of_car(%Car{settings: %CarSettings{enabled: false}}), do: {:ok, :disabled}

  defp start_vehicle_of_car(%Car{} = car) do
    with {:ok, :started} <- start_vehicle(car), do: {:ok, :started, car}
  end

  defp unique_violation?(errors) do
    Enum.any?(errors, fn
      {field, {_msg, opts}} when field in [:vin, :eid, :vid] ->
        Keyword.get(opts, :constraint) == :unique

      _ ->
        false
    end)
  end

  @spec start_vehicle(Car.t()) :: {:ok, :started | :running} | {:error, term}
  defp start_vehicle(%Car{} = car), do: GenServer.call(@name, {:start_vehicle, car})

  defp block_until_started(0), do: {:error, :restart_failed}

  defp block_until_started(retries) when retries > 0 do
    with pid when is_pid(pid) <- Process.whereis(@name),
         true <- Process.alive?(pid) do
      :ok
    else
      _ ->
        Process.sleep(10)
        block_until_started(retries - 1)
    end
  end

  defp list_vehicles! do
    case TeslaMate.Api.list_vehicles() do
      {:error, :not_signed_in} ->
        fallback_vehicles()

      {:error, :too_many_request, retry_after} ->
        Logger.warning("Could not get vehicles: rate limited, retry after #{retry_after}s")
        fallback_vehicles()

      {:error, reason} ->
        Logger.warning("Could not get vehicles: #{inspect(reason)}")
        fallback_vehicles()

      {:ok, []} ->
        fallback_vehicles()

      {:ok, vehicles} ->
        vehicles
    end
  end

  defp fallback_vehicles do
    vehicles =
      Log.list_cars()
      |> Enum.map(fn %Car{eid: eid, vid: vid, vin: vin, name: name} ->
        %TeslaApi.Vehicle{id: eid, vin: vin, vehicle_id: vid, display_name: name}
      end)

    if vehicles != [] do
      Logger.warning("Using fallback vehicles:\n\n#{inspect(vehicles, pretty: true)}")
    end

    vehicles
  end

  def create_or_update!(%TeslaApi.Vehicle{} = vehicle) do
    {:ok, %Car{} = car} = create_or_update(vehicle)
    car
  end

  @spec create_or_update(TeslaApi.Vehicle.t()) :: {:ok, Car.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update(%TeslaApi.Vehicle{} = vehicle) do
    with nil <- Log.get_car_by(vin: vehicle.vin),
         nil <- Log.get_car_by(vid: vehicle.vehicle_id),
         nil <- Log.get_car_by(eid: vehicle.id) do
      %Car{settings: default_settings(vehicle)}
    end
    |> Car.changeset(%{
      name: vehicle.display_name,
      eid: vehicle.id,
      vid: vehicle.vehicle_id,
      vin: vehicle.vin
    })
    |> Log.create_or_update_car()
  end

  defp default_settings(%TeslaApi.Vehicle{} = vehicle) do
    case Vehicle.identify(vehicle) do
      {:ok, %{model: m, trim_badging: trim_badging, marketing_name: marketing_name}}
      when m in ["S", "X"] and (trim_badging == nil or is_binary(marketing_name)) ->
        %CarSettings{suspend_min: 12}

      {:ok, %{model: m}} when m in ["3", "Y", "Cybertruck"] ->
        %CarSettings{suspend_min: 12}

      _ ->
        %CarSettings{}
    end
  end
end
