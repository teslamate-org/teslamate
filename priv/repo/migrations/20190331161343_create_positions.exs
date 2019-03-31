defmodule TeslaMate.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add(:date, :utc_datetime, null: false)
      add(:latitude, :float, null: false)
      add(:longitude, :float, null: false)
      add(:speed, :integer)
      add(:power, :integer)
      add(:odometer, :float)
      add(:ideal_battery_range, :float)
      add(:battery_level, :float)
      add(:outside_temp, :float)
      add(:altitude, :float)
    end
  end
end
