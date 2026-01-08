defmodule TeslaMate.Repo.Migrations.ReplaceDateBtreeIndexesWithBrin do
  use Ecto.Migration

  def change do
    # Drop BTREE indexes
    drop_if_exists(index(:positions, [:drive_id, :date]))
    drop_if_exists(index(:positions, [:date]))

    # Create BRIN indexes
    create(index(:positions, [:date], using: "brin"))
    create(index(:positions, [:drive_id, :date], using: "brin"))
  end
end
