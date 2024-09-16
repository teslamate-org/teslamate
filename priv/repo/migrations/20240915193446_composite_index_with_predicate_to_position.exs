defmodule TeslaMate.Repo.Migrations.AddCompositeIndexWithPredicateToPositions do
  use Ecto.Migration

  def change do
    create index(:positions, [:car_id, :date, "(ideal_battery_range_km IS NOT NULL)"],
             where: "ideal_battery_range_km IS NOT NULL"
           )
  end
end
