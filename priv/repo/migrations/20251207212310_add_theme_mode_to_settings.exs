defmodule TeslaMate.Repo.Migrations.AddThemeModeToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:theme_mode, :text, null: false, default: "light")
    end
  end
end
