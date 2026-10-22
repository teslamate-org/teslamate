defmodule TeslaMate.Repo.Migrations.DropUnusedIndexes do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:positions, ["ll_to_earth(latitude, longitude)"], using: "gist"))
    drop_if_exists(index(:addresses, ["ll_to_earth(latitude, longitude)"], using: "gist"))
  end
end
