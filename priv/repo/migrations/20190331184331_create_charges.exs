defmodule TeslaMate.Repo.Migrations.CreateCharges do
  use Ecto.Migration

  def change do
    create table(:charges) do
      add(:date, :utc_datetime, null: false)
      add(:ideal_battery_range, :float, null: false)
      add(:battery_level, :float, null: false)
      add(:charge_energy_added, :float, null: false)
      add(:charger_power, :float, null: false)
      add(:charger_voltage, :integer)
      add(:charger_phases, :integer)
      add(:charger_actual_current, :integer)
      add(:outside_temp, :float)
    end
  end
end
