defmodule TeslaMate.Repo.Migrations.AddCompositeIndexToPositions do
  use Ecto.Migration

  def change do
    create index(:positions, [:drive_id, :date])
    drop index(:positions, [:drive_id])
  end
end
