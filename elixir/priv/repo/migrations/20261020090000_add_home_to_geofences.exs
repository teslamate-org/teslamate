defmodule TeslaMate.Repo.Migrations.AddHomeToGeofences do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add(:home, :boolean, null: false, default: false)
    end

    create(unique_index(:geofences, [:home], where: "home", name: :geofences_single_home_index))
  end
end
