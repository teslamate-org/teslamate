defmodule TeslaMate.Repo.Migrations.AddBatteryRange do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:battery_range_km, :float)
    end
  end
end
