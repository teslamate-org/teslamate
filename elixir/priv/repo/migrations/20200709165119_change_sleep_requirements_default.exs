defmodule TeslaMate.Repo.Migrations.ChangeSleepRequirementsDefault do
  use Ecto.Migration

  def up do
    alter table(:car_settings) do
      modify(:req_not_unlocked, :boolean, null: false, default: false)
    end
  end

  def down do
    alter table(:car_settings) do
      modify(:req_not_unlocked, :boolean, null: false, default: true)
    end
  end
end
