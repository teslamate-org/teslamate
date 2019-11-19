defmodule TeslaMate.Repo.Migrations.GeofenceSleep do
  use Ecto.Migration

  def change do
    alter table(:car_settings) do
      add(:sleep_mode_enabled, :boolean, null: false, default: true)
    end
  end
end
