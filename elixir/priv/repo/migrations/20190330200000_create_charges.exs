defmodule TeslaMate.Repo.Migrations.CreateCharges do
  use Ecto.Migration

  def change do
    create table(:charges) do
      add(:date, :utc_datetime, null: false)
      add(:battery_heater_on, :boolean)
      add(:battery_level, :integer)
      add(:charge_energy_added, :float, null: false)
      add(:charger_actual_current, :integer)
      add(:charger_phases, :integer)
      add(:charger_pilot_current, :integer)
      add(:charger_power, :float, null: false)
      add(:charger_voltage, :integer)
      add(:fast_charger_present, :boolean)
      add(:conn_charge_cable, :string)
      add(:fast_charger_brand, :string)
      add(:fast_charger_type, :string)
      add(:ideal_battery_range_km, :float, null: false)
      add(:not_enough_power_to_heat, :boolean)
      add(:outside_temp, :float)

      add(:charging_process_id, references(:charging_processes), null: false)
    end
  end
end
