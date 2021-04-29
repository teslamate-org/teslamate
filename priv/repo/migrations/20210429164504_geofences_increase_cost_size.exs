defmodule TeslaMate.Repo.Migrations.GeofencesIncreaseCostSize do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      modify(:cost_per_unit, :decimal, precision: 7 , scale: 4, from: :decimal, precision: 6 , scale: 4)
			modify(:session_fee, :decimal, precision: 7 , scale: 2, from: :decimal, precision: 6 , scale: 2)      
    end
  end

  def down do
    alter table(:geofences) do
      modify(:cost_per_unit, :decimal, precision: 6 , scale: 4, from: :decimal, precision: 7 , scale: 4)
      modify(:session_fee, :decimal, precision: 6 , scale: 2, from: :decimal, precision: 7 , scale: 2)
    end
  end   
end
