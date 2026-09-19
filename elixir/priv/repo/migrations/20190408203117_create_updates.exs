defmodule TeslaMate.Repo.Migrations.CreateUpdates do
  use Ecto.Migration

  def change do
    create table(:updates) do
      add(:start_date, :utc_datetime, null: false)
      add(:end_date, :utc_datetime)
      add(:version, :string)

      add(:car_id, references(:cars), null: false)
    end
  end
end
