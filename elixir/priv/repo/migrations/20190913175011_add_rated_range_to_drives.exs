defmodule TeslaMate.Repo.Migrations.AddRatedRangeToDrives do
  use Ecto.Migration

  def change do
    rename(table(:positions), :battery_range_km, to: :rated_battery_range_km)

    rename(table(:drives), :start_range_km, to: :start_ideal_range_km)
    rename(table(:drives), :end_range_km, to: :end_ideal_range_km)

    alter table(:drives) do
      add(:start_rated_range_km, :float)
      add(:end_rated_range_km, :float)
      remove(:efficiency, :float)
    end

    alter table(:charges) do
      add(:rated_battery_range_km, :float)
    end

    rename(table(:charging_processes), :start_range_km, to: :start_ideal_range_km)
    rename(table(:charging_processes), :end_range_km, to: :end_ideal_range_km)

    alter table(:charging_processes) do
      add(:start_rated_range_km, :float)
      add(:end_rated_range_km, :float)
      remove(:calculated_max_range, :float)
    end
  end
end
