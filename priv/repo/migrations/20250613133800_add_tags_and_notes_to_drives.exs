defmodule TeslaMate.Repo.Migrations.AddTagsAndNotesToDrives do
  use Ecto.Migration

  def change do
    # Add notes field to drives table
    alter table(:drives) do
      add :notes, :text
    end

    # Create tags table for reusable tags
    create table(:tags) do
      add :name, :string, null: false
      add :color, :string, default: "#6c757d" # Default gray color

      timestamps()
    end

    create unique_index(:tags, [:name])

    # Create drive_tags join table for many-to-many relationship
    create table(:drive_tags) do
      add :drive_id, references(:drives, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:drive_tags, [:drive_id, :tag_id])
    create index(:drive_tags, [:drive_id])
    create index(:drive_tags, [:tag_id])
  end
end
