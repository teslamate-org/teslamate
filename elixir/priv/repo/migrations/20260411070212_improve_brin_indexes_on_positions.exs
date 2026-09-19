defmodule TeslaMate.Repo.Migrations.ImproveBrinIndexesOnPositions do
  use Ecto.Migration

  def change do
    # Drop existing BRIN indexes
    drop_if_exists(index(:positions, [:drive_id, :date]))
    drop_if_exists(index(:positions, [:date]))

    # Create new BRIN indexes with optimized options
    create(
      index(:positions, ["date timestamp_minmax_multi_ops"],
        using: "brin",
        options: "autosummarize = true, pages_per_range = 64"
      )
    )

    create(
      index(:positions, [:drive_id, "date timestamp_minmax_multi_ops"],
        using: "brin",
        options: "autosummarize = true, pages_per_range = 64"
      )
    )
  end
end
