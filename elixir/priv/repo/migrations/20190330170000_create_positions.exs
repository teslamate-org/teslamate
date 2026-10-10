defmodule TeslaMate.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add(:date, :utc_datetime, null: false)
      add(:latitude, :float, null: false)
      add(:longitude, :float, null: false)
      add(:speed, :integer)
      add(:power, :float)
      add(:odometer, :float)
      add(:ideal_battery_range_km, :float)
      add(:battery_level, :integer)
      add(:outside_temp, :float)
      add(:altitude, :float)
      add(:fan_status, :integer)
      add(:driver_temp_setting, :float)
      add(:passenger_temp_setting, :float)
      add(:is_climate_on, :boolean)
      add(:is_rear_defroster_on, :boolean)
      add(:is_front_defroster_on, :boolean)

      add(:car_id, references(:cars), null: false)
      add(:trip_id, references(:trips))
    end
  end
end
