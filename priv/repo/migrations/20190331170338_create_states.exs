defmodule TeslaMate.Repo.Migrations.CreateStates do
  use Ecto.Migration

  alias TeslaMate.Log.State.State

  def up do
    State.create_type()

    create table(:states) do
      add(:state, State.type(), null: false)

      add(:start_date, :utc_datetime, null: false)
      add(:end_date, :utc_datetime)

      add(:start_position_id, references(:positions))
      add(:end_position_id, references(:positions))
    end
  end

  def down do
    drop(table(:states))
    execute("DROP TYPE states_status")
  end
end
