defmodule TeslaMate.Repo.Migrations.LocationBasedChargeCostIncreaseScale do
  use Ecto.Migration

  def up do
    alter table(:geofences) do
      modify(:cost_per_kwh, :decimal, precision: 6, scale: 4)
    end
  end

  def down do
    alter table(:geofences) do
      modify(:cost_per_kwh, :decimal, precision: 6, scale: 2)
    end
  end
end
