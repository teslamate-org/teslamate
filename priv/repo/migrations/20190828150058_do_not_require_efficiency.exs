defmodule TeslaMate.Repo.Migrations.DoNotRequireEfficiency do
  use Ecto.Migration

  def up do
    alter table(:cars) do
      modify(:efficiency, :float, null: true)
      modify(:model, :string, null: true)
    end

    rename(table(:cars), :version, to: :trim_badging)
  end

  def down do
    alter table(:cars) do
      modify(:efficiency, :float, null: false)
      modify(:model, :string, null: false)
    end

    rename(table(:cars), :trim_badging, to: :version)
  end
end
