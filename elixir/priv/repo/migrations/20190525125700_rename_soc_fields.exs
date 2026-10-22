defmodule TeslaMate.Repo.Migrations.RenameSocFields do
  use Ecto.Migration

  def change do
    rename(table(:charging_processes), :start_soc, to: :start_range_km)
    rename(table(:charging_processes), :end_soc, to: :end_range_km)
  end
end
