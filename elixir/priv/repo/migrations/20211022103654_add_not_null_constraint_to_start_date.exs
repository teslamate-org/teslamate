defmodule TeslaMate.Repo.Migrations.AddNotNullConstraintToStartDate do
  use Ecto.Migration

  def up do
    alter table(:charging_processes) do
      modify(:start_date, :utc_datetime_usec, null: false)
    end
  end

  def down do
    alter table(:charging_processes) do
      modify(:start_date, :utc_datetime_usec, null: true)
    end
  end
end
