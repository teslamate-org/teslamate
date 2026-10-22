defmodule TeslaMate.Repo.Migrations.PhaseCorrection do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add(:phase_correction, :integer, null: true)
    end
  end
end
