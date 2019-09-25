defmodule TeslaMate.Repo.Migrations.CreateGeoExtensions do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION cube", "DROP EXTENSION cube")
    execute("CREATE EXTENSION earthdistance", "DROP EXTENSION earthdistance")
    create(index(:geofences, ["(earth_box(ll_to_earth(latitude, longitude), radius))"]))
  end
end
