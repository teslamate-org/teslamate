defmodule TeslaMate.Maintenance do
  @moduledoc """
  Lists and closes supported maintenance candidates.

  Mutations are disabled by default. Every action locks and rechecks the exact
  record immediately before using the existing logging domain functions.
  """

  import Ecto.Query, warn: false
  import Core.Dependency, only: [call: 3]

  require Logger

  alias TeslaMate.{Log, Repo, Vehicles}
  alias TeslaMate.Log.{Car, ChargingProcess, Drive}

  @default_open_after_seconds 2 * 24 * 60 * 60
  @default_limit 200
  @known_logger_states [:online, :asleep, :offline, :updating, :driving, :charging]

  defmodule Candidate do
    @moduledoc "An open record eligible for review on the maintenance page."

    @enforce_keys [:id, :entity_type, :entity_id, :car_id, :car_name, :started_at]
    defstruct @enforce_keys
  end

  defmodule CandidateList do
    @moduledoc "A bounded list of maintenance candidates."

    @enforce_keys [:checked_at, :open_after_seconds, :candidates, :truncated?]
    defstruct @enforce_keys
  end

  @type entity_type :: :drive | :charging_process
  @type error_reason ::
          :disabled
          | :invalid_request
          | :not_eligible
          | :vehicle_active
          | :runtime_unavailable
          | :insufficient_data
          | :failed

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []) do
    source = Keyword.get(opts, :config, Application.get_env(:teslamate, :maintenance_actions, []))
    get_value(source, :enabled, false) == true
  end

  def default_open_after_seconds, do: @default_open_after_seconds

  def candidates(opts \\ []) do
    checked_at = Keyword.get(opts, :now, DateTime.utc_now())

    open_after_seconds =
      positive_integer_option!(opts, :open_after_seconds, @default_open_after_seconds)

    limit = positive_integer_option!(opts, :limit, @default_limit)
    cutoff = DateTime.add(checked_at, -open_after_seconds, :second)

    candidates =
      cutoff
      |> open_candidates(limit + 1)
      |> Enum.sort_by(fn candidate ->
        {
          DateTime.to_unix(candidate.started_at, :microsecond),
          candidate.entity_type,
          candidate.entity_id
        }
      end)

    %CandidateList{
      checked_at: checked_at,
      open_after_seconds: open_after_seconds,
      candidates: Enum.take(candidates, limit),
      truncated?: length(candidates) > limit
    }
  end

  @spec close(entity_type(), pos_integer(), keyword()) ::
          {:ok, %{entity_type: entity_type(), entity_id: pos_integer(), outcome: :closed}}
          | {:error, error_reason()}
  def close(entity_type, entity_id, opts \\ []) do
    with true <- enabled?(opts) || {:error, :disabled},
         :ok <- validate_request(entity_type, entity_id) do
      close_eligible(entity_type, entity_id, opts)
    end
  rescue
    _error -> {:error, :failed}
  end

  defp close_eligible(entity_type, entity_id, opts) do
    checked_at = Keyword.get(opts, :now, DateTime.utc_now())

    open_after_seconds = Keyword.get(opts, :open_after_seconds, @default_open_after_seconds)

    cutoff = DateTime.add(checked_at, -open_after_seconds, :second)

    vehicle_activity =
      Keyword.get_lazy(opts, :vehicle_activity, fn ->
        fn car_id, type -> vehicle_activity(car_id, type, opts) end
      end)

    Repo.transaction(fn ->
      with entity when not is_nil(entity) <- eligible_entity(entity_type, entity_id, cutoff),
           :inactive <- vehicle_activity.(entity.car_id, entity_type) do
        close_entity(entity_type, entity)
      else
        nil -> Repo.rollback(:not_eligible)
        :active -> Repo.rollback(:vehicle_active)
        :unavailable -> Repo.rollback(:runtime_unavailable)
        _unexpected -> Repo.rollback(:runtime_unavailable)
      end
    end)
    |> case do
      {:ok, entity} ->
        Logger.info("Maintenance closed #{entity_type} ##{entity.id}", car_id: entity.car_id)

        {:ok, %{entity_type: entity_type, entity_id: entity.id, outcome: :closed}}

      {:error, reason}
      when reason in [
             :not_eligible,
             :vehicle_active,
             :runtime_unavailable,
             :insufficient_data
           ] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :failed}
    end
  end

  defp eligible_entity(:drive, entity_id, cutoff) do
    Drive
    |> where(
      [drive],
      drive.id == ^entity_id and is_nil(drive.end_date) and drive.start_date < ^cutoff
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp eligible_entity(:charging_process, entity_id, cutoff) do
    ChargingProcess
    |> where(
      [charging_process],
      charging_process.id == ^entity_id and is_nil(charging_process.end_date) and
        charging_process.start_date < ^cutoff
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp open_candidates(cutoff, limit) do
    open_drives(cutoff, limit) ++ open_charging_processes(cutoff, limit)
  end

  defp open_drives(cutoff, limit) do
    Drive
    |> join(:inner, [drive], car in Car, on: car.id == drive.car_id)
    |> where([drive], is_nil(drive.end_date) and drive.start_date < ^cutoff)
    |> order_by([drive], asc: drive.start_date, asc: drive.id)
    |> limit(^limit)
    |> select([drive, car], %Candidate{
      id: fragment("concat('drive:', ?)", drive.id),
      entity_type: :drive,
      entity_id: drive.id,
      car_id: car.id,
      car_name: car.name,
      started_at: drive.start_date
    })
    |> Repo.all()
  end

  defp open_charging_processes(cutoff, limit) do
    ChargingProcess
    |> join(:inner, [charging_process], car in Car, on: car.id == charging_process.car_id)
    |> where(
      [charging_process],
      is_nil(charging_process.end_date) and charging_process.start_date < ^cutoff
    )
    |> order_by([charging_process], asc: charging_process.start_date, asc: charging_process.id)
    |> limit(^limit)
    |> select([charging_process, car], %Candidate{
      id: fragment("concat('charging_process:', ?)", charging_process.id),
      entity_type: :charging_process,
      entity_id: charging_process.id,
      car_id: car.id,
      car_name: car.name,
      started_at: charging_process.start_date
    })
    |> Repo.all()
  end

  defp close_entity(:drive, drive) do
    case Log.close_drive(drive, lookup_address: false, delete_invalid: false) do
      {:ok, entity} -> entity
      {:error, :insufficient_data} -> Repo.rollback(:insufficient_data)
      {:error, _reason} -> Repo.rollback(:failed)
    end
  end

  defp close_entity(:charging_process, charging_process) do
    case Log.complete_charging_process(charging_process) do
      {:ok, entity} -> entity
      {:error, _reason} -> Repo.rollback(:failed)
    end
  end

  defp vehicle_activity(car_id, entity_type, opts) do
    active_state = if entity_type == :drive, do: :driving, else: :charging
    source = Keyword.get(opts, :config, Application.get_env(:teslamate, :maintenance_actions, []))
    vehicles = Keyword.get(opts, :vehicles, get_value(source, :vehicles, Vehicles))

    with %{state: logger_state} <- call(vehicles, :summary, [car_id]) do
      cond do
        logger_state == active_state -> :active
        logger_state in @known_logger_states -> :inactive
        true -> :unavailable
      end
    else
      _ -> :unavailable
    end
  rescue
    _error -> :unavailable
  catch
    :exit, _reason -> :unavailable
  end

  defp validate_request(entity_type, entity_id)
       when entity_type in [:drive, :charging_process] and is_integer(entity_id) and entity_id > 0,
       do: :ok

  defp validate_request(_entity_type, _entity_id), do: {:error, :invalid_request}

  defp positive_integer_option!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      value -> raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp get_value(source, key, default) when is_list(source), do: Keyword.get(source, key, default)
  defp get_value(source, key, default) when is_map(source), do: Map.get(source, key, default)
  defp get_value(_source, _key, default), do: default
end
