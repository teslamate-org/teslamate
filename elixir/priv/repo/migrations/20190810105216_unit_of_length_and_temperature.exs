defmodule TeslaMate.Repo.Migrations.UnitOfLengthAndTemperature do
  use Ecto.Migration

  alias TeslaMate.Repo

  import Ecto.Query

  def up do
    [use_imperial_units?] =
      from(s in "settings", select: s.use_imperial_units)
      |> Repo.all()

    execute("CREATE TYPE length AS ENUM ('km', 'mi')")
    execute("CREATE TYPE temperature AS ENUM ('C', 'F')")

    alter table(:settings) do
      add(:unit_of_length, :length, default: "km", null: false)
      add(:unit_of_temperature, :temperature, default: "C", null: false)
      remove(:use_imperial_units)
    end

    flush()

    {unit_of_length, unit_of_temperature} =
      case use_imperial_units? do
        false -> {"km", "C"}
        true -> {"mi", "F"}
      end

    from(t in "settings",
      update: [
        set: [
          unit_of_length: ^unit_of_length,
          unit_of_temperature: ^unit_of_temperature
        ]
      ]
    )
    |> Repo.update_all([])
  end

  def down do
    alter table(:settings) do
      remove(:unit_of_length)
      remove(:unit_of_temperature)
      add(:use_imperial_units, :boolean, default: false, null: false)
    end

    execute("DROP TYPE length")
    execute("DROP TYPE temperature")
  end
end
