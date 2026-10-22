defmodule TeslaMate.Repo.Migrations.AddNotNullConstraintToDisplayPriority do
  use Ecto.Migration

  def up do
    alter table(:cars) do
      modify(:display_priority, :smallint, null: false, default: 1)
    end
  end

  def down do
    alter table(:cars) do
      modify(:display_priority, :smallint, null: true, default: 1)
    end
  end
end
