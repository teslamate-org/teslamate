defmodule TeslaMate.Repo.Migrations.AddHideDetailsToGeofences do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add :hide_details, :boolean, null: false, default: false
    end
  end
end
