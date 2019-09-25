defmodule TeslaMate.Repo.Migrations.CreateIndexOnAddressPositions do
  use Ecto.Migration

  def change do
    create(index(:addresses, ["ll_to_earth(latitude, longitude)"]))
  end
end
