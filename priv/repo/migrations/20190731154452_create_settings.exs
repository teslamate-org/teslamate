defmodule TeslaMate.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  import Ecto.Query

  alias TeslaMate.Settings.Settings
  alias TeslaMate.Repo

  def up do
    create table(:settings) do
      add(:use_imperial_units, :boolean, default: false, null: false)

      timestamps()
    end

    flush()

    %Settings{}
    |> Settings.changeset(%{use_imperial_units: false})
    |> Repo.insert!()
  end

  def down do
    drop(table(:settings))
  end
end
