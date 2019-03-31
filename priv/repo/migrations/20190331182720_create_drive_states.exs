defmodule TeslaMate.Repo.Migrations.CreateDriveStates do
  use Ecto.Migration

  def change do
    create table(:drive_states) do
      add(:start_date, :utc_datetime, null: false)
      add(:end_date, :utc_datetime)

      add(:outside_temp_avg, :float)
      add(:speed_max, :integer)
      add(:speed_min, :integer)
      add(:power_max, :float)
      add(:power_min, :float)
      add(:power_avg, :float)

      add(:start_position_id, references(:positions), null: false)
      add(:end_position_id, references(:positions))
    end
  end
end
