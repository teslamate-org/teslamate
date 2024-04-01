defmodule TeslaMate.Repo.Migrations.AddCompositeIndexToPositionsOnOdometer do
  use Ecto.Migration

  def change do
    create index(:positions, [:odometer, :car_id])
  end
end
