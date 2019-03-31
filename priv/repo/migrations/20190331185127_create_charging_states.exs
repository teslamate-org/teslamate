defmodule TeslaMate.Repo.Migrations.CreateChargingStates do
  use Ecto.Migration

  def change do
    create table(:charging_states) do
      add(:start_date, :utc_datetime, nul: false)
      add(:end_date, :utc_datetime)

      add(:unplug_date, :utc_datetime)
      add(:charge_energy_added, :float)

      add(:position_id, references(:positions))
      add(:charge_start_id, references(:charges))
      add(:charge_end_id, references(:charges))
    end
  end
end
