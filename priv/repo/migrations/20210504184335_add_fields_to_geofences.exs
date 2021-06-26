defmodule TeslaMate.Repo.Migrations.AddFieldsToGeofences do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  def up do
    alter table(:geofences) do
      add :currency_code, references(:currencies, column: :currency_code, type: :string, size: 3),
        null: true

      add :country_code, references(:countries, column: :country_code, type: :string, size: 2),
        null: true

      add :supercharger, :boolean, default: true
      add :provider, :string, null: true
      add :active, :boolean, default: true
      add :charger_code, :string, size: 5
    end

    flush()

    from(g in "geofences", update: [set: [charger_code: g.id]])
    |> TeslaMate.Repo.update_all([])

    create unique_index(:geofences, [:charger_code])

    alter table(:geofences) do
      modify :charger_code, :string, null: false
    end
  end

  def down do
    alter table(:geofences) do
      remove_if_exists(:currency_code, :string)
      remove_if_exists(:country_code, :string)
      remove_if_exists(:supercharger, :boolean)
      remove_if_exists(:provider, :string)
      remove_if_exists(:active, :boolean)
      remove_if_exists(:charger_code, :string)
    end

    drop_if_exists unique_index(:geofences, [:charger_code])
  end
end
