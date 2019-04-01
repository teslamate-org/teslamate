defmodule TeslaMate.Repo.Migrations.CreateCharges do
  use Ecto.Migration

  def change do
    create table(:charges) do
      add(:date, :utc_datetime, null: false)
      add(:ideal_battery_range_km, :float, null: false)
      add(:battery_level, :integer, null: false)
      add(:charge_energy_added, :float, null: false)
      add(:charger_power, :float, null: false)
      add(:charger_voltage, :integer)
      add(:charger_phases, :integer)
      add(:charger_actual_current, :integer)
      add(:outside_temp, :float)

      add(:charging_process_id, references(:charging_processes), null: false)
    end
  end
end
