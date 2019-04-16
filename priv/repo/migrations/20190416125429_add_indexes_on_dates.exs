defmodule TeslaMate.Repo.Migrations.AddIndexesOnDates do
  use Ecto.Migration

  def change do
    create(index(:positions, [:date]))
    create(index(:charges, [:date]))
  end
end
