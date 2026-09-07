defmodule TeslaMate.Vehicles do
  use Supervisor

  require Logger

  alias __MODULE__.Vehicle
  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Log.Car
  alias TeslaMate.Log

  @name __MODULE__
  @status_key {__MODULE__, :status}
  @parent_key {__MODULE__, :parent}
  @restart_lock {__MODULE__, :restart}
  @topic "vehicles"

  @typedoc """
  State of the vehicle logging as of the last (re)start of this supervisor.

  `:ok` means the Tesla API returned at least one vehicle. With
  `{:error, :no_vehicles}` the account has none yet; the other API errors
  mean the `TeslaMate.Api.list_vehicles/0` call failed and the cars already
  known from the database were used instead. `:restarting` is set while a
  `restart/0` is in progress and `{:error, {:start_failed, reason}}` when the
  supervisor could not be started again, in which case no vehicle is logged
  until the next `restart/0`.
  """
  @type status ::
          :ok
          | :restarting
          | {:error,
             :no_vehicles | :not_signed_in | :too_many_request | {:start_failed, term} | term}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Summaries of the logged vehicles. Empty while the supervisor is not running
  or a `restart/0` is in progress; the new supervisor is registered before its
  discovery finishes, so waiting for its children would block on the API call.
  """
  def list do
    with false <- status() == :restarting,
         pid when is_pid(pid) <- Process.whereis(@name) do
      summaries(pid)
    else
      _ -> []
    end
  end

  defp summaries(pid) do
    Supervisor.which_children(pid)
    |> Task.async_stream(fn {_, pid, _, _} -> Vehicle.summary(pid) end,
      ordered: false,
      max_concurrency: 10,
      timeout: 5000
    )
    |> Enum.map(fn {:ok, vehicle} -> vehicle end)
    |> Enum.sort_by(fn %Vehicle.Summary{car: %Car{id: id, display_priority: dp}} ->
      {dp, id}
    end)
  end

  @spec status() :: status
  def status do
    :persistent_term.get(@status_key, :ok)
  end

  def kill do
    Logger.warning("Restarting #{__MODULE__} supervisor")
    __MODULE__ |> Process.whereis() |> Process.exit(:kill)
  end

  @doc """
  Stops every vehicle process and starts the supervisor again, which runs the
  vehicle discovery anew.

  The supervisor is terminated and restarted explicitly through its parent.
  Unlike stopping it and relying on the parent's automatic restart, this does
  not count toward the parent's restart intensity, so repeated calls cannot
  take the application down. The price is that a failed start is not retried
  by the parent: it is recorded in `status/0` and needs another `restart/0`.
  Restarts are serialized; a concurrent one returns `{:error, :restarting}`.
  Subscribers (see `subscribe/0`) are notified with
  `{TeslaMate.Vehicles, :reloaded}` once the new vehicle processes run.
  """
  @spec restart() :: :ok | {:error, term}
  def restart do
    case :global.trans(@restart_lock, &do_restart/0, [node()], 0) do
      :aborted -> {:error, :restarting}
      result -> result
    end
  end

  defp do_restart do
    with {:ok, parent} <- parent() do
      :persistent_term.put(@status_key, :restarting)

      with :ok <- Supervisor.terminate_child(parent, @name),
           {:ok, _pid} <- restart_child(parent) do
        :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, @topic, {__MODULE__, :reloaded})
      else
        {:error, reason} ->
          Logger.error("Restarting #{__MODULE__} failed: #{inspect(reason)}")
          :persistent_term.put(@status_key, {:error, {:start_failed, reason}})
          {:error, reason}
      end
    end
  end

  @doc "Subscribes the caller to `{TeslaMate.Vehicles, :reloaded}` messages."
  def subscribe do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)
  end

  @doc false
  def topic, do: @topic

  defdelegate summary(id), to: Vehicle
  defdelegate resume_logging(id), to: Vehicle
  defdelegate suspend_logging(id), to: Vehicle
  defdelegate subscribe_to_summary(id), to: Vehicle
  defdelegate subscribe_to_fetch(id), to: Vehicle

  # Callbacks

  @impl true
  def init(opts) do
    # Remembered for restart/0: after a failed start there is no process left
    # to look the parent up from.
    {:parent, parent} = Process.info(self(), :parent)
    :persistent_term.put(@parent_key, parent)

    {vehicles, status} =
      case Keyword.fetch(opts, :vehicles) do
        {:ok, vehicles} -> {vehicles, :ok}
        :error -> discover_vehicles()
      end

    :persistent_term.put(@status_key, status)

    children =
      vehicles
      |> Enum.map(&{Keyword.get(opts, :vehicle, Vehicle), car: create_or_update!(&1)})
      |> Enum.uniq_by(fn {_mod, car: %Car{id: id}} -> id end)
      |> Enum.filter(fn {_mod, car: %Car{settings: settings}} -> settings.enabled end)

    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end

  # Private

  defp parent do
    with pid when is_pid(pid) <- :persistent_term.get(@parent_key, nil),
         true <- Process.alive?(pid) do
      {:ok, pid}
    else
      _ -> {:error, :not_running}
    end
  end

  defp restart_child(parent) do
    case Supervisor.restart_child(parent, @name) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      # A concurrent restart won the race; its vehicle processes are fresh.
      {:error, :running} -> {:ok, Process.whereis(@name)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp discover_vehicles do
    case TeslaMate.Api.list_vehicles() do
      {:ok, []} ->
        {fallback_vehicles(), {:error, :no_vehicles}}

      {:ok, vehicles} ->
        {vehicles, :ok}

      {:error, :not_signed_in} ->
        {fallback_vehicles(), {:error, :not_signed_in}}

      {:error, :too_many_request, retry_after} ->
        Logger.warning("Could not get vehicles: rate limited, retry after #{retry_after}s")
        {fallback_vehicles(), {:error, :too_many_request}}

      {:error, reason} ->
        Logger.warning("Could not get vehicles: #{inspect(reason)}")
        {fallback_vehicles(), {:error, reason}}
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
    unless is_nil(name = vehicle.display_name), do: Logger.info("Starting logger for '#{name}'")

    {:ok, %Car{} = car} =
      with nil <- Log.get_car_by(vin: vehicle.vin),
           nil <- Log.get_car_by(vid: vehicle.vehicle_id),
           nil <- Log.get_car_by(eid: vehicle.id) do
        settings =
          case Vehicle.identify(vehicle) do
            {:ok, %{model: m, trim_badging: trim_badging, marketing_name: marketing_name}}
            when m in ["S", "X"] and (trim_badging == nil or is_binary(marketing_name)) ->
              %CarSettings{suspend_min: 12}

            {:ok, %{model: m}} when m in ["3", "Y", "Cybertruck"] ->
              %CarSettings{suspend_min: 12}

            _ ->
              %CarSettings{}
          end

        %Car{settings: settings}
      end
      |> Car.changeset(%{
        name: vehicle.display_name,
        eid: vehicle.id,
        vid: vehicle.vehicle_id,
        vin: vehicle.vin
      })
      |> Log.create_or_update_car()

    car
  end
end
