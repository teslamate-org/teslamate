defmodule TeslaMate.Repo.Migrations.AddEstBatteryRangeKm do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:est_battery_range_km, :float)
    end
  end
end
