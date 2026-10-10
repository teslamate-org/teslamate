defmodule TeslaMate.Repo.Migrations.AddConstraints do
  use Ecto.Migration

  def change do
    create(unique_index(:states, [:car_id, "(end_date IS NULL)"], where: "end_date IS NULL"))
    create(constraint(:states, :positive_duration, check: "end_date >= start_date"))
    create(constraint(:updates, :positive_duration, check: "end_date >= start_date"))
  end
end
