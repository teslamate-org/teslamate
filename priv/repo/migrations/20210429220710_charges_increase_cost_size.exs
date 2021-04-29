defmodule TeslaMate.Repo.Migrations.ChargesIncreaseCostSize do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 8 , scale: 2, from: :decimal, precision: 6 , scale: 2)
    end
  end

  def down do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 6 , scale: 2, from: :decimal, precision: 8 , scale: 2)
    end
  end 
end
