defmodule TeslaMate.Repo.Migrations.AddCompositeIndexToPositionsOnOdometer do
  use Ecto.Migration

  def change do
    create index(:positions, [:car_id, :odometer])
  end
end
