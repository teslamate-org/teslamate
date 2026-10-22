defmodule TeslaMate.Repo.Migrations.AddUniqueIndexOnVins do
  use Ecto.Migration

  def change do
    create(unique_index(:cars, :vin))
  end
end
