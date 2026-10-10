defmodule TeslaMate.Repo.Migrations.PersistSuspendSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add(:suspend_min, :integer, default: 12, null: false)
      add(:suspend_after_idle_min, :integer, default: 15, null: false)
    end
  end
end
