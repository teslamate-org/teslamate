defmodule TeslaMate.Repo.Migrations.AddBatteryHeaterFields do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add(:battery_heater, :boolean)
      add(:battery_heater_on, :boolean)
      add(:battery_heater_no_power, :boolean)
    end

    alter table(:charges) do
      add(:battery_heater, :boolean)
      add(:battery_heater_no_power, :boolean)
    end
  end
end
