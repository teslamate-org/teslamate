defmodule TeslaMate.Repo.Migrations.CreateGeoExtensions do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS cube WITH SCHEMA public", "DROP EXTENSION cube")

    execute(
      "CREATE EXTENSION IF NOT EXISTS earthdistance WITH SCHEMA public",
      "DROP EXTENSION earthdistance"
    )

    execute("ALTER FUNCTION ll_to_earth SET search_path = public")
    execute("ALTER FUNCTION earth_box SET search_path = public")
    create(index(:geofences, ["(earth_box(ll_to_earth(latitude, longitude), radius))"]))
  end
end
