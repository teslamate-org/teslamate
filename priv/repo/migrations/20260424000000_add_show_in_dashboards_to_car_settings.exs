defmodule TeslaMate.Repo.Migrations.AddShowInDashboardsToCarSettings do
  use Ecto.Migration

  def change do
    alter table(:car_settings) do
      add :show_in_dashboards, :boolean, null: false, default: true
    end
  end
end
