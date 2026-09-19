defmodule TeslaMate.Repo.Migrations.GeofenceSleep do
  use Ecto.Migration

  def change do
    alter table(:car_settings) do
      add(:sleep_mode_enabled, :boolean, null: false, default: true)
    end

    create table(:geofence_sleep_mode_whitelist, primary_key: false) do
      add(:car_id, references(:cars, on_delete: :delete_all), primary_key: true)
      add(:geofence_id, references(:geofences, on_delete: :delete_all), primary_key: true)
    end

    create table(:geofence_sleep_mode_blacklist, primary_key: false) do
      add(:car_id, references(:cars, on_delete: :delete_all), primary_key: true)
      add(:geofence_id, references(:geofences, on_delete: :delete_all), primary_key: true)
    end
  end
end
