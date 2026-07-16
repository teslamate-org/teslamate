defmodule TeslaMate.Import.Run do
  @moduledoc false

  use Ecto.Schema

  schema "import_runs" do
    field :source_key, :string
    field :status, Ecto.Enum, values: [:running, :complete, :abandoned]
    field :timezone, :string
    field :date_limit, :utc_datetime_usec
    field :date_limit_captured, :boolean, default: false
    field :car_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule TeslaMate.Import.FileCheckpoint do
  @moduledoc false

  use Ecto.Schema

  schema "import_file_checkpoints" do
    field :file_name, :string
    field :file_fingerprint, :string
    field :completed_at, :utc_datetime_usec
    field :run_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule TeslaMate.Import.Rejection do
  @moduledoc false

  use Ecto.Schema

  schema "import_rejections" do
    field :file_name, :string
    field :file_fingerprint, :string
    field :row, :integer

    field :reason, Ecto.Enum,
      values: [
        :invalid_fields,
        :parse_error,
        :invalid_date,
        :ambiguous_local_time,
        :nonexistent_local_time,
        :invalid_timezone,
        :column_count_mismatch
      ]

    field :fields, {:array, :string}, default: []
    field :run_id, :integer

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule TeslaMate.Import.Checkpoint do
  @moduledoc false

  import Ecto.Query

  alias TeslaMate.Import.{FileCheckpoint, RejectedRow, Rejection, RejectionReport, Run}
  alias TeslaMate.Repo

  @max_examples 100

  def source_key(path) do
    path
    |> Path.expand()
    |> hash()
  end

  def file_fingerprint(path) do
    try do
      digest =
        path
        |> File.stream!(64 * 1024, [])
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)

      {:ok, digest}
    rescue
      e in File.Error -> {:error, e.reason}
    end
  end

  def file_id(%{path: path, fingerprint: fingerprint}) do
    {Path.basename(path), fingerprint}
  end

  def get_active_run(source_key) do
    Run
    |> where(source_key: ^source_key, status: :running)
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  def start_run(source_key, timezone) do
    now = DateTime.utc_now()

    %Run{
      source_key: source_key,
      status: :running,
      timezone: timezone,
      inserted_at: now,
      updated_at: now
    }
    |> Repo.insert()
  end

  def abandon_run(run_id), do: set_run_status(run_id, :abandoned)
  def complete_run(run_id), do: set_run_status(run_id, :complete)

  def set_car(run_id, car_id) do
    now = DateTime.utc_now()

    {1, _} =
      Run
      |> where(id: ^run_id)
      |> Repo.update_all(set: [car_id: car_id, updated_at: now])

    :ok
  end

  def capture_date_limit(run_id, date_limit) do
    now = DateTime.utc_now()

    {1, _} =
      Run
      |> where(id: ^run_id, date_limit_captured: false)
      |> Repo.update_all(
        set: [date_limit: date_limit, date_limit_captured: true, updated_at: now]
      )

    :ok
  end

  def completed_files(run_id) do
    FileCheckpoint
    |> where(run_id: ^run_id)
    |> select([f], {f.file_name, f.file_fingerprint})
    |> Repo.all()
    |> MapSet.new()
  end

  def complete_file(run_id, {file_name, file_fingerprint}) do
    now = DateTime.utc_now()

    {_, _} =
      Repo.insert_all(
        FileCheckpoint,
        [
          %{
            run_id: run_id,
            file_name: file_name,
            file_fingerprint: file_fingerprint,
            completed_at: now,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: [set: [completed_at: now, updated_at: now]],
        conflict_target: [:run_id, :file_name, :file_fingerprint]
      )

    :ok
  end

  def record_rejection(run_id, %RejectedRow{file_fingerprint: fingerprint} = rejected_row)
      when is_binary(fingerprint) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.insert_all(
        Rejection,
        [
          %{
            run_id: run_id,
            file_name: rejected_row.file,
            file_fingerprint: fingerprint,
            row: rejected_row.row,
            reason: rejected_row.reason,
            fields: rejected_row.fields,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:run_id, :file_name, :file_fingerprint, :row]
      )

    if count == 1, do: :inserted, else: :existing
  end

  def rejection_report(_run_id, []), do: %RejectionReport{}

  def rejection_report(run_id, file_ids) do
    identity_filter =
      Enum.reduce(file_ids, dynamic(false), fn {file_name, fingerprint}, filter ->
        dynamic(
          [r],
          ^filter or (r.file_name == ^file_name and r.file_fingerprint == ^fingerprint)
        )
      end)

    query =
      Rejection
      |> where([r], r.run_id == ^run_id)
      |> where(^identity_filter)

    count = Repo.aggregate(query, :count, :id)

    examples =
      query
      |> order_by(asc: :id)
      |> limit(@max_examples)
      |> Repo.all()
      |> Enum.map(fn rejection ->
        RejectedRow.new(
          rejection.file_name,
          rejection.row,
          rejection.reason,
          rejection.fields,
          rejection.file_fingerprint
        )
      end)

    %RejectionReport{count: count, examples: examples}
  end

  defp set_run_status(run_id, status) do
    now = DateTime.utc_now()

    {1, _} =
      Run
      |> where(id: ^run_id)
      |> Repo.update_all(set: [status: status, updated_at: now])

    :ok
  end

  defp hash(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
