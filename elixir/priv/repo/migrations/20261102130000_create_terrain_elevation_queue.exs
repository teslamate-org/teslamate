defmodule TeslaMate.Repo.Migrations.CreateTerrainElevationQueue do
  use Ecto.Migration

  def change do
    # The closed drives that wait for Terrain to add the elevation their
    # positions lack: a drive of any age, closed by the vehicle or by hand,
    # gets it even across restarts. Processing state, kept out of drives,
    # which dashboards and other apps read; a deleted drive leaves the queue.
    create table(:terrain_elevation_queue, primary_key: false) do
      add :drive_id, references(:drives, type: :integer, on_delete: :delete_all),
        primary_key: true
    end
  end
end
