defmodule TeslaMate.Repo.Migrations.CreateStates do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE states_status AS ENUM ('online', 'offline', 'asleep')",
            "DROP TYPE states_status "

    create table(:states) do
      add(:state, :states_status, null: false)

      add(:start_date, :utc_datetime, null: false)
      add(:end_date, :utc_datetime)

      add(:car_id, references(:cars), null: false)
    end
  end
end
