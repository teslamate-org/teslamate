defmodule TeslaMate.Repo.Migrations.UnitOfLegnthAndTemperature do
  use Ecto.Migration

  alias TeslaMate.Repo

  import Ecto.Query

  defmodule Units.Length do
    use EctoEnum.Postgres, type: :length, enums: [:km, :mi]
  end

  defmodule Units.Temperature do
    use EctoEnum.Postgres, type: :temperature, enums: [:C, :F]
  end

  def up do
    [use_imperial_units?] =
      from(s in "settings", select: s.use_imperial_units)
      |> Repo.all()

    Units.Length.create_type()
    Units.Temperature.create_type()

    alter table(:settings) do
      add(:unit_of_length, Units.Length.type(), default: "km", null: false)
      add(:unit_of_temperature, Units.Temperature.type(), default: "C", null: false)
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

    execute("DROP TYPE Length")
    execute("DROP TYPE temperature")
  end
end
