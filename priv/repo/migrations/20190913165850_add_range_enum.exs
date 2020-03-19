defmodule TeslaMate.Repo.Migrations.AddRangeEnum do
  use Ecto.Migration

  alias TeslaMate.Settings.Range

  def change do
    Range.create_type()

    alter table(:settings) do
      add(:preferred_range, Range.type(), default: "rated", null: false)
    end
  end
end
