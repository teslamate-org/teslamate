defmodule TeslaMate.Repo.Migrations.AddCenterDisplayStateToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :center_display_state, :smallint
    end
  end
end
