defmodule TeslaMate.Repo.Migrations.AddFlatFee do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add(:session_fee, :decimal, precision: 6, scale: 2)
    end
  end
end
