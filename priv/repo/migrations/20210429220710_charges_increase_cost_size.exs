defmodule TeslaMate.Repo.Migrations.ChargesIncreaseCostSize do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      modify(:cost, :decimal, precision: 10, scale: 4, from: :decimal, precision: 6, scale: 2)
    end
  end
end
