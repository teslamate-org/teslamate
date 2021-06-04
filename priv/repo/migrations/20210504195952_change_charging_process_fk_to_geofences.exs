defmodule TeslaMate.Repo.Migrations.ChangeChargingProcessFkToGeofences do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      modify :geofence_id,
             references(:geofences, column: :id, type: :integer, on_delete: :restrict),
             null: true,
             from: references(:geofences, column: :id, type: :integer, on_delete: :nilify_all),
             null: true
    end
  end
end
