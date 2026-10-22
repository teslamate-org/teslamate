defmodule TeslaMate.Repo.Migrations.AddLanguage do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:language, :text, null: false, default: "en")
    end
  end
end
