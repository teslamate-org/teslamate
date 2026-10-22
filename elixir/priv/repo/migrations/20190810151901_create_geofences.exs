defmodule TeslaMate.Repo.Migrations.CreateGeofences do
  use Ecto.Migration

  def change do
    create table(:geofences) do
      add(:name, :string, null: false)
      add(:latitude, :float, null: false)
      add(:longitude, :float, null: false)
      add(:radius, :float, null: false, default: 25)

      add(:address_id, references(:addresses), null: false)

      timestamps()
    end

    create(unique_index(:geofences, :address_id))
  end
end
