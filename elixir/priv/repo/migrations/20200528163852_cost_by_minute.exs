defmodule TeslaMate.Repo.Migrations.CostByMinute do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE billing_type AS ENUM ('per_kwh', 'per_minute')"

    alter table(:geofences) do
      add :billing_type, :billing_type, null: false, default: "per_kwh"
    end

    rename table(:geofences), :cost_per_kwh, to: :cost_per_unit
  end

  def down do
    rename table(:geofences), :cost_per_unit, to: :cost_per_kwh

    alter table(:geofences) do
      remove :billing_type
    end

    execute "DROP TYPE billing_type"
  end
end
