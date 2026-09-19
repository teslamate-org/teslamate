defmodule TeslaMate.Repo.Migrations.DropCpConfidenceAndInterval do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      remove(:charge_energy_used_confidence, :float)
      remove(:interval_sec, :integer)
    end
  end
end
