defmodule TeslaMate.Repo.Migrations.CreateChargingProcesses do
  use Ecto.Migration

  def change do
    create table(:charging_processes) do
      # Note the typo: 'nul' – This is fixed in 20211022103654_add_not_null_constraint_to_start_date
      add(:start_date, :utc_datetime, nul: false)
      add(:end_date, :utc_datetime)
      add(:charge_energy_added, :float)
      add(:start_soc, :float)
      add(:end_soc, :float)
      add(:start_battery_level, :integer)
      add(:end_battery_level, :integer)
      add(:calculated_max_range, :integer)
      add(:duration_min, :integer)
      add(:outside_temp_avg, :float)

      add(:car_id, references(:cars), null: false)
      add(:position_id, references(:positions), null: false)
    end
  end
end
