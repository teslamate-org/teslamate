defmodule TeslaMate.Repo.Migrations.CreateTerrainElevationQueue do
  use Ecto.Migration

  def change do
    # The closed drives that wait for Terrain to add the elevation their
    # positions lack: a drive of any age, closed by the vehicle or by hand,
    # gets it even across restarts. Processing state, kept out of drives,
    # which dashboards and other apps read; a deleted drive leaves the queue.
    # attempted_at is when Terrain last tried the drive and a lookup failed:
    # a pass takes the drives tried longest ago last, so a drive whose
    # lookups keep failing never holds back the others, also across restarts.
    create table(:terrain_elevation_queue, primary_key: false) do
      add :drive_id, references(:drives, type: :integer, on_delete: :delete_all),
        primary_key: true

      add :attempted_at, :utc_datetime_usec
    end
  end
end
