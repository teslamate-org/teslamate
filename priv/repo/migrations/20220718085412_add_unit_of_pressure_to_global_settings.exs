defmodule TeslaMate.Repo.Migrations.AddUnitOfPressureToGlobalSettings do
  use Ecto.Migration

  def change do
    execute("CREATE TYPE unit_of_pressure AS ENUM ('bar', 'psi')", "DROP TYPE unit_of_pressure ")

    alter table(:settings) do
      add(:unit_of_pressure, :unit_of_pressure, default: "bar", null: false)
    end
  end
end
