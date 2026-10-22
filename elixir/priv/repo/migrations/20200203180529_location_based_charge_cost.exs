defmodule TeslaMate.Repo.Migrations.LocationBasedChargeCost do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add(:cost_per_kwh, :decimal, precision: 6, scale: 2)
    end

    alter table(:car_settings) do
      add(:free_supercharging, :boolean, null: false, default: false)
    end
  end
end
