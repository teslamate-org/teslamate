defmodule TeslaMate.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  alias TeslaMate.Repo

  def up do
    create table(:settings) do
      add(:use_imperial_units, :boolean, default: false, null: false)
      timestamps()
    end

    flush()

    Ecto.Adapters.SQL.query!(
      Repo,
      "INSERT INTO settings (use_imperial_units, inserted_at, updated_at) VALUES ($1, $2, $3)",
      [
        false,
        DateTime.utc_now(),
        DateTime.utc_now()
      ]
    )
  end

  def down do
    drop(table(:settings))
  end
end
