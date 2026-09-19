defmodule TeslaMate.Repo.Migrations.AddAddressToChargingProcess do
  use Ecto.Migration

  def change do
    alter table(:charging_processes) do
      add(:address_id, references(:addresses))
    end
  end
end
