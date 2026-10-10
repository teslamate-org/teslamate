defmodule TeslaMate.Repo.Migrations.AddImportCheckpoints do
  use Ecto.Migration

  def change do
    create table(:import_runs) do
      add :source_key, :string, null: false
      add :status, :string, null: false
      add :timezone, :string, null: false
      add :date_limit, :utc_datetime_usec
      add :date_limit_captured, :boolean, null: false, default: false
      add :car_id, references(:cars, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:import_runs, [:source_key],
        where: "status = 'running'",
        name: :import_runs_one_running_per_source
      )
    )

    create table(:import_file_checkpoints) do
      add :run_id, references(:import_runs, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :file_fingerprint, :string, null: false
      add :completed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :import_file_checkpoints,
        [:run_id, :file_name, :file_fingerprint],
        name: :import_file_checkpoints_identity
      )
    )

    create table(:import_rejections) do
      add :run_id, references(:import_runs, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :file_fingerprint, :string, null: false
      add :row, :integer, null: false
      add :reason, :string, null: false
      add :fields, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :import_rejections,
        [:run_id, :file_name, :file_fingerprint, :row],
        name: :import_rejections_row_identity
      )
    )
  end
end
