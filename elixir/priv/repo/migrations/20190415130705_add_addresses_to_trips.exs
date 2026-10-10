defmodule TeslaMate.Repo.Migrations.AddAddressesToTrips do
  use Ecto.Migration

  def change do
    alter table(:trips) do
      remove(:start_address, :string)
      remove(:end_address, :string)

      add(:start_address_id, references(:addresses))
      add(:end_address_id, references(:addresses))
    end
  end
end
