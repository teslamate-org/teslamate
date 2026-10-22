defmodule TeslaMate.Repo.Migrations.AddUsableBatteryLevel do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:usable_battery_level, :integer)
    end
  end
end
