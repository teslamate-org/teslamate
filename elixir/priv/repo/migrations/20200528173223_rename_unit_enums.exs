defmodule TeslaMate.Repo.Migrations.RenameUnitEnums do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TYPE length RENAME TO unit_of_length",
      "ALTER TYPE unit_of_length RENAME TO length"
    )

    execute(
      "ALTER TYPE temperature RENAME TO unit_of_temperature",
      "ALTER TYPE unit_of_temperature RENAME TO temperature"
    )
  end
end
