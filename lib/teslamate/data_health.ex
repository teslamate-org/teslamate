defmodule TeslaMate.DataHealth do
  @moduledoc """
  Read-only checks for TeslaMate data that may need manual review.

  The report intentionally does not repair, close or delete records. It only
  surfaces drives and charging sessions that have remained open past a bounded
  age so a user can inspect them before choosing a maintenance action. Long-running
  does not by itself mean the data is corrupt.
  """

  import Ecto.Query, warn: false

  alias TeslaMate.Log.{Car, ChargingProcess, Drive}
  alias TeslaMate.Repo

  @default_open_after_seconds 2 * 24 * 60 * 60
  @default_limit 200

  defmodule Finding do
    @moduledoc "A read-only data-health finding backed by database records."

    @enforce_keys [
      :id,
      :code,
      :entity_type,
      :entity_id,
      :car_id,
      :car_name,
      :started_at
    ]
    defstruct @enforce_keys
  end

  defmodule Report do
    @moduledoc "A read-only data-health report."

    @enforce_keys [
      :checked_at,
      :open_after_seconds,
      :findings,
      :truncated?,
      :read_only?
    ]
    defstruct @enforce_keys
  end

  @doc """
  Returns long-running open drives and charging sessions without changing the database.

  Options are accepted to make the age boundary and result cap deterministic in
  tests. A record is long-running only when it started strictly before the cutoff.
  """
  def report(opts \\ []) do
    checked_at = Keyword.get(opts, :now, DateTime.utc_now())

    open_after_seconds =
      positive_integer_option!(opts, :open_after_seconds, @default_open_after_seconds)

    limit = positive_integer_option!(opts, :limit, @default_limit)
    cutoff = DateTime.add(checked_at, -open_after_seconds, :second)

    candidates =
      cutoff
      |> long_running_candidates(limit + 1)
      |> Enum.sort_by(fn candidate ->
        {
          DateTime.to_unix(candidate.started_at, :microsecond),
          candidate.entity_type,
          candidate.entity_id
        }
      end)

    truncated? = length(candidates) > limit
    selected = Enum.take(candidates, limit)

    findings =
      Enum.map(selected, fn candidate ->
        %Finding{
          id: "#{candidate.entity_type}:#{candidate.entity_id}",
          code: finding_code(candidate.entity_type),
          entity_type: candidate.entity_type,
          entity_id: candidate.entity_id,
          car_id: candidate.car_id,
          car_name: candidate.car_name,
          started_at: candidate.started_at
        }
      end)

    %Report{
      checked_at: checked_at,
      open_after_seconds: open_after_seconds,
      findings: findings,
      truncated?: truncated?,
      read_only?: true
    }
  end

  defp positive_integer_option!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      value -> raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp long_running_candidates(cutoff, limit) do
    long_running_drives(cutoff, limit) ++ long_running_charging_processes(cutoff, limit)
  end

  defp long_running_drives(cutoff, limit) do
    Drive
    |> join(:inner, [drive], car in Car, on: car.id == drive.car_id)
    |> where([drive], is_nil(drive.end_date) and drive.start_date < ^cutoff)
    |> order_by([drive], asc: drive.start_date, asc: drive.id)
    |> limit(^limit)
    |> select([drive, car], %{
      entity_type: :drive,
      entity_id: drive.id,
      car_id: car.id,
      car_name: car.name,
      started_at: drive.start_date
    })
    |> Repo.all()
  end

  defp long_running_charging_processes(cutoff, limit) do
    ChargingProcess
    |> join(:inner, [charging_process], car in Car, on: car.id == charging_process.car_id)
    |> where(
      [charging_process],
      is_nil(charging_process.end_date) and charging_process.start_date < ^cutoff
    )
    |> order_by([charging_process], asc: charging_process.start_date, asc: charging_process.id)
    |> limit(^limit)
    |> select([charging_process, car], %{
      entity_type: :charging_process,
      entity_id: charging_process.id,
      car_id: car.id,
      car_name: car.name,
      started_at: charging_process.start_date
    })
    |> Repo.all()
  end

  defp finding_code(:drive), do: :long_running_open_drive

  defp finding_code(:charging_process),
    do: :long_running_open_charging_process
end
