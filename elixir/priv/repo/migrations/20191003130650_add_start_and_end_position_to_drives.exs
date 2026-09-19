defmodule TeslaMate.Repo.Migrations.AddStartAndEndPositionToDrives do
  use Ecto.Migration

  def change do
    alter table(:drives) do
      add(:start_position_id, references(:positions))
      add(:end_position_id, references(:positions))

      add(:start_geofence_id, references(:geofences))
      add(:end_geofence_id, references(:geofences))
    end

    alter table(:charging_processes) do
      add(:geofence_id, references(:geofences))
    end

    alter table(:addresses) do
      remove(:geofence_id, references(:geofences))
    end

    create(index(:positions, ["ll_to_earth(latitude, longitude)"]))
  end
end
