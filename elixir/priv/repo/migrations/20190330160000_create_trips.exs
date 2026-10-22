defmodule TeslaMate.Repo.Migrations.CreateTrips do
  use Ecto.Migration

  def change do
    create table(:trips) do
      add(:start_date, :utc_datetime, null: false)
      add(:end_date, :utc_datetime)
      add(:outside_temp_avg, :float)
      add(:speed_max, :integer)
      add(:power_max, :float)
      add(:power_min, :float)
      add(:power_avg, :float)
      add(:start_range_km, :float)
      add(:end_range_km, :float)
      add(:start_km, :float)
      add(:end_km, :float)
      add(:distance, :float)
      add(:duration_min, :integer)
      add(:start_address, :string)
      add(:end_address, :string)
      add(:consumption_kWh, :float)
      add(:consumption_kWh_100km, :float)
      add(:efficiency, :float)

      add(:car_id, references(:cars), null: false)
    end
  end
end
