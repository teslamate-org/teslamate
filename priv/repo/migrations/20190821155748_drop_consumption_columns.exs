defmodule TeslaMate.Repo.Migrations.DropConsumptionColumns do
  use Ecto.Migration

  def change do
    alter table(:drives) do
      remove(:consumption_kWh)
      remove(:consumption_kWh_100km)
    end
  end
end
