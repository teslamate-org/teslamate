defmodule TeslaMate.Repo.Migrations.AddCostFieldToCharges do
  use Ecto.Migration

  def change do

    alter table(:charges) do
      add(:cost, :decimal(6,2))
    end

  end
end
