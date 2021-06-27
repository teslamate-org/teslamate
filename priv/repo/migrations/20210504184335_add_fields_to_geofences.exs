defmodule TeslaMate.Repo.Migrations.AddFieldsToGeofences do
  use Ecto.Migration

  def up do
    alter table(:geofences) do
      add :currency_code, references(:currencies, column: :currency_code, type: :string, size: 3),
        null: true

      add :supercharger, :boolean, default: true
    end
  end

  def down do
    alter table(:geofences) do
      remove_if_exists(:currency_code, :string)
      remove_if_exists(:supercharger, :boolean)
    end
  end
end
