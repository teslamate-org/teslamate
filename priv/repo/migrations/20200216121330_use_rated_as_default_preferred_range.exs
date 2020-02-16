defmodule TeslaMate.Repo.Migrations.UseRatedAsDefaultPreferredRange do
  use Ecto.Migration

  alias TeslaMate.Settings.Range

  def up do
    alter table(:settings) do
      modify(:preferred_range, Range.type(), default: "rated", null: false)
    end
  end

  def down do
    alter table(:settings) do
      modify(:preferred_range, Range.type(), default: "ideal", null: false)
    end
  end
end
