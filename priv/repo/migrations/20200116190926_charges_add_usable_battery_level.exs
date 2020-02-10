defmodule TeslaMate.Repo.Migrations.ChargesAddUsableBatteryLevel do
  use Ecto.Migration

  def change do
    alter table(:charges) do
      add(:usable_battery_level, :integer)
    end
  end
end
