defmodule TeslaMate.Maintenance do
  @moduledoc """
  Revalidates and closes a supported data-health finding.

  Mutations are disabled by default. Every action locks and rechecks the exact
  record immediately before using the existing logging domain functions.
  """

  import Ecto.Query, warn: false
  import Core.Dependency, only: [call: 3]

  require Logger

  alias TeslaMate.{DataHealth, Log, Repo, Vehicles}
  alias TeslaMate.Log.{ChargingProcess, Drive}

  @known_logger_states [:online, :asleep, :offline, :updating, :driving, :charging]

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

    open_after_seconds =
      Keyword.get(opts, :open_after_seconds, DataHealth.default_open_after_seconds())

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

  defp get_value(source, key, default) when is_list(source), do: Keyword.get(source, key, default)
  defp get_value(source, key, default) when is_map(source), do: Map.get(source, key, default)
  defp get_value(_source, _key, default), do: default
end
