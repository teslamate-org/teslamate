defmodule TeslaMate.Repo.Migrations.AddEstTotalChargeEnergy do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      add(:charge_energy_used, :float)
      add(:charge_energy_used_confidence, :float)
      add(:interval_sec, :integer)
    end
  end
end
