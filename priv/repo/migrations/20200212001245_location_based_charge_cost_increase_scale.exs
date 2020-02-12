defmodule TeslaMate.Repo.Migrations.LocationBasedChargeCostIncreaseScale do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      modify(:cost_per_kwh, :decimal, precision: 6, scale: 4)
    end
  end
end
