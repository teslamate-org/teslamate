defmodule TeslaMate.Repo.Migrations.AddEnabledToCarSettings do
  use Ecto.Migration

  def change do
    alter table(:car_settings) do
      add :enabled, :boolean, null: false, default: true
    end
  end
end
