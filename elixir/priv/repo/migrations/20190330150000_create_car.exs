defmodule TeslaMate.Repo.Migrations.CreateCar do
  use Ecto.Migration

  def change do
    create table(:cars) do
      add(:eid, :bigint, null: false)
      add(:vid, :bigint, null: false)
      add(:model, :string, null: false)
      add(:efficiency, :float, null: false)

      timestamps()
    end

    create(unique_index(:cars, :eid))
    create(unique_index(:cars, :vid))
  end
end
