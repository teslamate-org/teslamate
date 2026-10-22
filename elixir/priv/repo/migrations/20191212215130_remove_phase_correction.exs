defmodule TeslaMate.Repo.Migrations.RemovePhaseCorrection do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      remove(:phase_correction, :integer, null: true)
    end
  end
end
