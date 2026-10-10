defmodule TeslaMate.Repo.Migrations.AddCostFieldToCharges do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      add(:cost, :decimal, precision: 6, scale: 2)
    end
  end
end
