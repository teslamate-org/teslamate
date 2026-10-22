defmodule TeslaMate.Repo.Migrations.UseRatedAsDefaultPreferredRange do
  use Ecto.Migration

  def up do
    alter table(:settings) do
      modify :preferred_range, :range, default: "rated", null: false
    end
  end

  def down do
    alter table(:settings) do
      modify :preferred_range, :range, default: "ideal", null: false
    end
  end
end
