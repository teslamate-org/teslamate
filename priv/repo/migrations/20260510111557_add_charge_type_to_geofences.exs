defmodule TeslaMate.Repo.Migrations.AddChargeTypeToGeofences do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add :charge_type, :string, null: true
    end
  end
end
