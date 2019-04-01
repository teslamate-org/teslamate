defmodule TeslaMate.Repo.Migrations.CreateChargingProcesses do
  use Ecto.Migration

  def change do
    create table(:charging_processes) do
      add(:start_date, :utc_datetime, nul: false)
      add(:end_date, :utc_datetime)

      add(:charge_energy_added, :float)

      add(:car_id, references(:cars), null: false)
      add(:position_id, references(:positions))
    end
  end
end
