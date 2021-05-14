defmodule TeslaMate.Repo.Migrations.ChargesIncreaseCostSize do
  use Ecto.Migration

  def up do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 10, scale: 4, from: :decimal, precision: 6, scale: 2)
    end
  end

  def down do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 6, scale: 2, from: :decimal, precision: 10, scale: 4)
    end
  end
end
