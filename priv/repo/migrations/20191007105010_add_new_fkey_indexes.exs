defmodule TeslaMate.Repo.Migrations.AddNewFkeyIndexes do
  use Ecto.Migration

  def change do
    create(index(:drives, [:start_position_id]))
    create(index(:drives, [:end_position_id]))
    create(index(:drives, [:start_geofence_id]))
    create(index(:drives, [:end_geofence_id]))

    drop(index(:positions, ["ll_to_earth(latitude, longitude)"]))
    drop(index(:addresses, ["ll_to_earth(latitude, longitude)"]))
    drop(index(:geofences, ["(earth_box(ll_to_earth(latitude, longitude), radius))"]))

    create(index(:positions, ["ll_to_earth(latitude, longitude)"], using: "gist"))
    create(index(:addresses, ["ll_to_earth(latitude, longitude)"], using: "gist"))
  end
end
