defmodule TeslaMate.Repo.Migrations.AddRatedRangeToDrives do
  use Ecto.Migration

  def change do
    rename(table(:drives), :start_range_km, to: :start_ideal_range_km)
    rename(table(:drives), :end_range_km, to: :end_ideal_range_km)

    alter table(:drives) do
      add(:start_rated_range_km, :float)
      add(:end_rated_range_km, :float)
      remove(:efficiency, :float)
    end
  end
end
