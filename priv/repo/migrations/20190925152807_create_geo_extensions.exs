defmodule TeslaMate.Repo.Migrations.CreateGeoExtensions do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS cube", "DROP EXTENSION cube")
    execute("CREATE EXTENSION IF NOT EXISTS earthdistance", "DROP EXTENSION earthdistance")
    create(index(:geofences, ["(earth_box(ll_to_earth(latitude, longitude), radius))"]))
  end
end
