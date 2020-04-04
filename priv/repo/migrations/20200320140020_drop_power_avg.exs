defmodule TeslaMate.Repo.Migrations.DropPowerAvg do
  use Ecto.Migration

  def change do
    alter table(:drives) do
      remove(:power_avg, :float)
    end
  end
end
