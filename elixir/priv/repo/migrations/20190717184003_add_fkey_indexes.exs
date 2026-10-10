defmodule TeslaMate.Repo.Migrations.AddFkeyIndexes do
  use Ecto.Migration

  def change do
    create(index(:charges, [:charging_process_id]))

    create(index(:charging_processes, [:car_id]))
    create(index(:charging_processes, [:position_id]))
    create(index(:charging_processes, [:address_id]))

    create(index(:positions, [:car_id]))
    create(index(:positions, [:trip_id]))

    create(index(:states, [:car_id]))

    create(index(:trips, [:car_id]))
    create(index(:trips, [:start_address_id]))
    create(index(:trips, [:end_address_id]))

    create(index(:updates, [:car_id]))
  end
end
